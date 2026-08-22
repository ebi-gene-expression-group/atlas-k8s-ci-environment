#!/usr/bin/env python3
"""Apply charts/openbao/acl/catalog.yaml to the running OpenBao (KV, Google OIDC, identity)."""
from __future__ import annotations

import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "charts/openbao/acl/catalog.yaml"
INIT_PATH = ROOT / "charts/openbao/.secrets-init-public.yaml"
OIDC_PATH = ROOT / "charts/openbao/.secrets-oidc-public.yaml"
KV_VALUES_PATH = ROOT / "charts/openbao/.secrets-kv-public.yaml"
GXA_CHART = ROOT / "charts/gxa"
BAO_ADDR = os.environ.get("BAO_ADDR", "https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk")
ACTOR = os.environ.get("OPENBAO_ACTOR", "root")


def load_yaml(path: Path) -> dict:
    text = path.read_text()
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(text)
    except ImportError:
        data = json.loads(
            subprocess.check_output(
                ["ruby", "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.load_file(ARGV[0]))", str(path)],
                text=True,
            )
        )
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected a mapping")
    return data


def yaml_scalar(path: Path, key: str) -> str:
    data = load_yaml(path)
    val = first_str(data, key)
    if val:
        return val
    raise SystemExit(f"{path}: missing {key}")


def first_str(data: dict, *keys: str) -> str:
    for key in keys:
        val = data.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
    return ""


def oidc_credentials(path: Path) -> tuple[str, str]:
    raw = load_yaml(path)
    oidc = raw.get("oidc") if isinstance(raw.get("oidc"), dict) else raw
    client_id = first_str(oidc, "client_id", "clientId")
    client_secret = first_str(oidc, "client_secret", "clientSecret")
    missing = [name for name, val in (("client_id", client_id), ("client_secret", client_secret)) if not val]
    if missing:
        raise SystemExit(
            f"{path}: missing {', '.join(missing)} "
            "(use client_id/client_secret or clientId/clientSecret under oidc:)"
        )
    return client_id, client_secret


class Bao:
    def __init__(self, addr: str, token: str) -> None:
        self.addr = addr.rstrip("/")
        self.token = token
        self.ctx = ssl._create_unverified_context()

    def request(self, method: str, path: str, body: dict | None = None, ok_404: bool = False):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(
            f"{self.addr}/v1/{path.lstrip('/')}",
            data=data,
            method=method,
            headers={"X-Vault-Token": self.token, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, context=self.ctx) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            err = exc.read().decode("utf-8", "replace")
            if ok_404 and exc.code == 404:
                return None
            if exc.code in (400, 204) and "already in use" in err.lower():
                return {}
            raise SystemExit(f"{method} {path}: HTTP {exc.code}\n{err}") from exc


def expand_secrets(catalog: dict) -> list[dict]:
    out: list[dict] = []
    for sset in catalog.get("secret_sets") or []:
        keys = sset.get("clusters") or sset.get("environments") or []
        for env in keys:
            for secret in sset["secrets"]:
                out.append(
                    {
                        "service": sset["service"],
                        "environment": env,
                        "class": secret["class"],
                        "name": secret["name"],
                        "description": secret.get("description", ""),
                    }
                )
    out.extend(catalog.get("secrets") or [])
    return out


def owner_group_for(catalog: dict, service: str) -> str:
    for gid, group in (catalog.get("groups") or {}).items():
        if service in (group.get("services") or []):
            return gid
    return ""


def kubernetes_namespace(catalog: dict, service: str, env: str) -> str:
    spec = (catalog.get("services") or {}).get(service) or {}
    return str((spec.get("namespaces") or {}).get(env) or "")


def oidc_mount(catalog: dict) -> str:
    return str((catalog.get("auth") or {}).get("oidc", {}).get("path") or "embl-ebi").strip("/")


def oidc_display_name(catalog: dict) -> str:
    return str((catalog.get("auth") or {}).get("oidc", {}).get("display_name") or "EMBL-EBI Login")


def remount(bao: Bao, src: str, dst: str) -> None:
    print(f"Remounting {src} -> {dst}")
    resp = bao.request("POST", "sys/remount", {"from": src, "to": dst})
    data = resp.get("data") or resp
    mid = data.get("migration_id")
    if not mid:
        return
    for _ in range(60):
        status_resp = bao.request("GET", f"sys/remount/status/{mid}")
        body = status_resp.get("data") or status_resp
        info = body.get("migration_info") if isinstance(body.get("migration_info"), dict) else {}
        status = str(
            body.get("migration_status") or body.get("status") or info.get("status") or ""
        ).lower()
        if status in ("success", "succeeded"):
            return
        if status in ("failure", "failed"):
            raise SystemExit(f"remount {src} -> {dst} failed: {body}")
        time.sleep(1)
    # File storage can finish without a status the poller understands.
    auths = _data(bao.request("GET", "sys/auth"))
    dest_key = dst.split("auth/", 1)[-1].strip("/") + "/"
    src_key = src.split("auth/", 1)[-1].strip("/") + "/"
    if dest_key in auths and src_key not in auths:
        return
    raise SystemExit(f"remount {src} -> {dst} timed out")


def access_caps(access: list[str]) -> list[str]:
    caps = ["read", "list"]
    if "write" in access:
        caps.extend(["create", "update", "patch", "delete"])
    return sorted(set(caps))


def policy_name(gid: str, role_name: str, service: str | None = None) -> str:
    if service:
        return f"group-{gid}-role-{role_name}-{service}"
    return f"group-{gid}-role-{role_name}"


def slim_group(group: dict, role_name: str, services: list[str]) -> dict:
    return {
        "display_name": group.get("display_name"),
        "services": services,
        "roles": {role_name: group["roles"][role_name]},
    }


def role_service_combos(group: dict) -> list[tuple[str | None, list[str]]]:
    """(service or None, services for that policy). None = every service in the group."""
    all_svcs = list(group.get("services") or [])
    combos: list[tuple[str | None, list[str]]] = [(None, all_svcs)]
    combos.extend((svc, [svc]) for svc in all_svcs)
    return combos


def membership_services(m: dict) -> list[str]:
    return [str(s) for s in (m.get("services") or [])]


def validate_catalog(catalog: dict) -> None:
    groups = catalog.get("groups") or {}
    for uname, user in (catalog.get("users") or {}).items():
        if not user.get("email"):
            raise SystemExit(f"catalog users.{uname}: email is required")
        memberships = user.get("memberships") or []
        if not memberships:
            raise SystemExit(f"catalog users.{uname}: at least one membership is required")
        for m in memberships:
            gid = m.get("group")
            role = m.get("role")
            if gid not in groups:
                raise SystemExit(f"catalog users.{uname}: unknown group {gid}")
            roles = groups[gid].get("roles") or {}
            if role not in roles:
                raise SystemExit(f"catalog users.{uname}: unknown role {role} in group {gid}")
            allowed = set(groups[gid].get("services") or [])
            extra = [s for s in membership_services(m) if s not in allowed]
            if extra:
                raise SystemExit(
                    f"catalog users.{uname}: service(s) {extra} not in group {gid} "
                    f"(allowed: {sorted(allowed) or 'none'})"
                )


def role_identity_members(
    catalog: dict, ids: dict[str, str], gid: str, role_name: str, service: str | None
) -> list[str]:
    out: list[str] = []
    for uname, spec in (catalog.get("users") or {}).items():
        for m in spec.get("memberships") or []:
            if m.get("group") != gid or m.get("role") != role_name:
                continue
            scoped = membership_services(m)
            if service is None and not scoped:
                out.append(ids[uname])
                break
            if service is not None and service in scoped:
                out.append(ids[uname])
                break
    return out


def policy_hcl(group_id: str, group: dict, catalog: dict | None = None) -> str:
    paths: dict[str, set[str]] = {}
    specs = (catalog or {}).get("services") or {}

    def add(path: str, caps: list[str]) -> None:
        paths.setdefault(path, set()).update(caps)

    def service_scope(svc: str) -> str:
        return str((specs.get(svc) or {}).get("scope") or "environment")

    add("kv/metadata", ["list"])
    for role in (group.get("roles") or {}).values():
        for grant in role.get("grants") or []:
            if not grant.get("all_kv"):
                continue
            caps = access_caps(grant.get("access") or ["read"])
            meta_caps = ["read", "list"] + (
                ["create", "update", "delete"] if "write" in (grant.get("access") or []) else []
            )
            add("kv/metadata/*", meta_caps)
            add("kv/data/*", caps)
    for svc in group.get("services") or []:
        add(f"kv/metadata/{svc}", ["list"])
        scope = service_scope(svc)
        for role in (group.get("roles") or {}).values():
            for grant in role.get("grants") or []:
                segments = grant.get("clusters") if scope == "cluster" else grant.get("environments")
                if not segments:
                    continue
                caps = access_caps(grant.get("access") or ["read"])
                meta_caps = ["read", "list"] + (
                    ["create", "update", "delete"] if "write" in (grant.get("access") or []) else []
                )
                for env in segments:
                    add(f"kv/metadata/{svc}/{env}", ["list"])
                    for cls in grant["classes"]:
                        add(f"kv/metadata/{svc}/{env}/{cls}", ["list"])
                        add(f"kv/data/{svc}/{env}/{cls}/*", caps)
                        add(f"kv/metadata/{svc}/{env}/{cls}/*", meta_caps)
    if not any(p.startswith("kv/data/") for p in paths):
        return ""
    blocks = [f"# group {group_id} ({group.get('display_name', group_id)})"]
    for path in sorted(paths):
        caps = ", ".join(f'"{c}"' for c in sorted(paths[path]))
        blocks.append(f'path "{path}" {{\n  capabilities = [{caps}]\n}}')
    return "\n\n".join(blocks) + "\n"


def lookup_values(values: dict | None, service: str, env: str, cls: str, name: str):
    cur: object = values or {}
    for key in (service, env, cls, name):
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur if isinstance(cur, dict) else None


def deep_merge(base: dict, overlay: dict) -> dict:
    out = dict(base)
    for key, val in overlay.items():
        if isinstance(val, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], val)
        else:
            out[key] = val
    return out


def load_gxa_helm(env: str) -> dict:
    merged: dict = {}
    for name in ("values.yaml", f"values-{env}.yaml", f".secrets-{env}.yaml"):
        path = GXA_CHART / name
        if path.is_file():
            merged = deep_merge(merged, load_yaml(path))
    return merged


def map_gxa_helm_to_kv(helm: dict) -> dict:
    """Map Helm .secrets-<env>.yaml (+ values) onto catalog class/name dicts."""
    out: dict = {}
    jdbc = helm.get("jdbc") or {}
    if jdbc.get("password"):
        out.setdefault("app", {})["jdbc"] = {
            "username": str(jdbc.get("user") or "atlasprd3"),
            "password": str(jdbc["password"]),
        }
    solr = helm.get("solr") or {}
    if solr.get("password"):
        out.setdefault("app", {})["solr"] = {
            "username": str(solr.get("user") or "admin"),
            "password": str(solr["password"]),
        }
    tomcat = helm.get("tomcat") or {}
    if tomcat.get("deployerPassword"):
        out.setdefault("ops", {})["tomcat-deployer"] = {
            "username": "deployer",
            "password": str(tomcat["deployerPassword"]),
        }
    if tomcat.get("curatorPassword"):
        out.setdefault("ops", {})["tomcat-curator"] = {
            "username": "curator",
            "password": str(tomcat["curatorPassword"]),
        }
    nginx = helm.get("nginx") or {}
    ops_auth = ((nginx.get("cache") or {}).get("purge") or {}).get("opsAuth") or {}
    if ops_auth.get("password"):
        out.setdefault("ops", {})["nginx-cache-purge"] = {
            "username": str(ops_auth.get("username") or "cacheops"),
            "password": str(ops_auth["password"]),
        }
    pg = helm.get("postgresql") or {}
    if pg.get("atlasdataloadPassword"):
        out.setdefault("ops", {})["postgres-atlasdataload"] = {
            "username": "atlasdataload",
            "password": str(pg["atlasdataloadPassword"]),
        }
    if pg.get("superuserPassword"):
        out.setdefault("ops", {})["postgres-superuser"] = {
            "username": str(pg.get("superuser") or "postgres"),
            "password": str(pg["superuserPassword"]),
        }
    return out


def load_kv_seed_values() -> dict:
    values: dict = {}
    envs: list[str] = []
    for path in sorted(GXA_CHART.glob(".secrets-*.yaml")):
        env = path.name.removeprefix(".secrets-").removesuffix(".yaml")
        mapped = map_gxa_helm_to_kv(load_gxa_helm(env))
        if mapped:
            values.setdefault("gxa", {})[env] = mapped
            envs.append(env)
    if envs:
        print(f"Loaded GXA Helm secrets for: {', '.join(envs)}")
    if KV_VALUES_PATH.is_file():
        print(f"Merging {KV_VALUES_PATH.name}")
        values = deep_merge(values, load_yaml(KV_VALUES_PATH))
    return values


def _data(resp: dict) -> dict:
    if isinstance(resp.get("data"), dict) and any(str(k).endswith("/") for k in resp["data"]):
        return resp["data"]
    return resp


def ensure_mounts(bao: Bao, catalog: dict) -> None:
    mounts = _data(bao.request("GET", "sys/mounts"))
    if "kv/" not in mounts:
        print("Enabling kv v2 at kv/")
        bao.request("POST", "sys/mounts/kv", {"type": "kv", "options": {"version": "2"}})
    mount = oidc_mount(catalog)
    display = oidc_display_name(catalog)
    auths = _data(bao.request("GET", "sys/auth"))
    wanted = f"{mount}/"
    if wanted not in auths:
        if "oidc/" in auths:
            remount(bao, "auth/oidc", f"auth/{mount}")
        else:
            print(f"Enabling oidc auth at {wanted}")
            bao.request(
                "POST",
                f"sys/auth/{mount}",
                {
                    "type": "oidc",
                    "description": display,
                    "config": {"listing_visibility": "unauth"},
                },
            )


def configure_oidc(bao: Bao, catalog: dict, client_id: str, client_secret: str) -> str:
    oidc = catalog["auth"]["oidc"]
    mount = oidc_mount(catalog)
    display = oidc_display_name(catalog)
    emails = sorted({u["email"] for u in (catalog.get("users") or {}).values() if u.get("email")})
    if not emails:
        raise SystemExit("catalog users: at least one email is required for the OIDC allowlist")
    print(f"OIDC allowlist: {len(emails)} email(s) (UI tab {mount}/)")
    bao.request(
        "POST",
        f"auth/{mount}/config",
        {
            "oidc_discovery_url": "https://accounts.google.com",
            "oidc_client_id": client_id,
            "oidc_client_secret": client_secret,
            "default_role": "google",
        },
    )
    bao.request(
        "POST",
        f"auth/{mount}/role/google",
        {
            "user_claim": "email",
            "allowed_redirect_uris": oidc["redirect_uris"],
            "oidc_scopes": "openid,email,profile",
            "bound_audiences": client_id,
            "bound_claims": {
                "email": emails,
                "hd": oidc.get("hosted_domains") or [],
            },
            "claim_mappings": {"email": "email", "name": "name"},
            "token_policies": [],
            "token_ttl": "8h",
            "role_type": "oidc",
        },
    )
    # Without listing_visibility=unauth the UI login page only shows Token.
    # The tab label is the mount path (spaces are not allowed).
    bao.request(
        "POST",
        f"sys/auth/{mount}/tune",
        {"listing_visibility": "unauth", "description": display},
    )
    try:
        bao.request(
            "POST",
            "sys/config/ui/login/default-auth/oidc",
            {
                "default_auth_type": "oidc",
                "backup_auth_types": ["token"],
            },
        )
    except SystemExit as exc:
        # OpenBao 2.6 may not have custom login settings; listing_visibility is enough.
        if "HTTP 4" not in str(exc):
            raise
    auths = _data(bao.request("GET", "sys/auth"))
    return auths[f"{mount}/"]["accessor"]


def write_policies(bao: Bao, catalog: dict) -> None:
    for gid, group in (catalog.get("groups") or {}).items():
        for role_name in (group.get("roles") or {}):
            for svc, services in role_service_combos(group):
                name = policy_name(gid, role_name, svc)
                hcl = policy_hcl(gid, slim_group(group, role_name, services), catalog)
                if not hcl:
                    print(f"Skip empty policy {name}")
                    continue
                print(f"Policy {name}")
                bao.request("PUT", f"sys/policies/acl/{name}", {"policy": hcl})


def entity_id(bao: Bao, name: str, email: str) -> str:
    existing = bao.request("GET", f"identity/entity/name/{name}", ok_404=True)
    if existing:
        eid = existing["data"]["id"]
        bao.request(
            "POST",
            f"identity/entity/id/{eid}",
            {"name": name, "metadata": {"email": email}},
        )
        return eid
    created = bao.request("POST", "identity/entity", {"name": name, "metadata": {"email": email}})
    return created["data"]["id"]


def ensure_alias(bao: Bao, eid: str, email: str, accessor: str) -> None:
    body = bao.request("GET", f"identity/entity/id/{eid}")
    for alias in body.get("data", {}).get("aliases") or []:
        if alias.get("mount_accessor") == accessor:
            if alias.get("name") != email:
                bao.request("POST", f"identity/entity-alias/id/{alias['id']}", {"name": email, "canonical_id": eid, "mount_accessor": accessor})
            return
    bao.request(
        "POST",
        "identity/entity-alias",
        {"name": email, "canonical_id": eid, "mount_accessor": accessor},
    )


def group_id(bao: Bao, name: str, policies: list[str], member_ids: list[str]) -> None:
    existing = bao.request("GET", f"identity/group/name/{name}", ok_404=True)
    payload = {
        "name": name,
        "type": "internal",
        "policies": policies,
        "member_entity_ids": member_ids,
    }
    if existing:
        bao.request("POST", f"identity/group/id/{existing['data']['id']}", payload)
        return
    bao.request("POST", "identity/group", payload)


def sync_identity(bao: Bao, catalog: dict, accessor: str) -> dict[str, str]:
    ids: dict[str, str] = {}
    for uname, user in (catalog.get("users") or {}).items():
        email = user["email"]
        eid = entity_id(bao, uname, email)
        ensure_alias(bao, eid, email, accessor)
        ids[uname] = eid
        print(f"User {uname} -> {email}")
    for gid, group in (catalog.get("groups") or {}).items():
        org_members = [
            ids[u]
            for u, spec in (catalog.get("users") or {}).items()
            if any(m.get("group") == gid for m in spec.get("memberships") or [])
        ]
        print(f"Group {gid} ({len(org_members)} members)")
        group_id(bao, gid, [], org_members)
        for role_name in group.get("roles") or {}:
            for svc, services in role_service_combos(group):
                policy = policy_name(gid, role_name, svc)
                role_members = role_identity_members(catalog, ids, gid, role_name, svc)
                hcl = policy_hcl(gid, slim_group(group, role_name, services), catalog)
                policies = [policy] if hcl else []
                label = f"{gid}-role-{role_name}" + (f"-{svc}" if svc else "")
                if role_members or hcl:
                    print(f"Group {label} ({len(role_members)} members)")
                group_id(bao, label, policies, role_members)
    return ids


def seed_kv(bao: Bao, catalog: dict, values: dict | None) -> None:
    if not values:
        print("No local Helm .secrets-*.yaml (or .secrets-kv-public.yaml); skipping KV seed")
        return
    seeded = 0
    missing: list[str] = []
    for item in expand_secrets(catalog):
        data = lookup_values(values, item["service"], item["environment"], item["class"], item["name"])
        path = f"{item['service']}/{item['environment']}/{item['class']}/{item['name']}"
        if not data:
            missing.append(path)
            continue
        print(f"KV put kv/data/{path}")
        bao.request("POST", f"kv/data/{path}", {"data": data})
        meta = bao.request("GET", f"kv/metadata/{path}", ok_404=True) or {}
        custom = dict((meta.get("data") or {}).get("custom_metadata") or {})
        created_by = custom.get("created_by") or ACTOR
        custom.update(
            {
                "description": item.get("description") or "",
                "owner_group": owner_group_for(catalog, item["service"]),
                "service": item["service"],
                "environment": item["environment"],
                "class": item["class"],
                "created_by": created_by,
                "updated_by": ACTOR,
                "source": "helm-or-kv-seed",
            }
        )
        ns = kubernetes_namespace(catalog, item["service"], item["environment"])
        if ns:
            custom["kubernetes_namespace"] = ns
        # KV v2 rejects empty custom_metadata values (must be 1–512 chars).
        custom = {k: v for k, v in custom.items() if isinstance(v, str) and v}
        bao.request("POST", f"kv/metadata/{path}", {"custom_metadata": custom})
        seeded += 1
    print(f"KV seed: {seeded} written")
    if missing:
        print("KV seed skipped (not in local .secrets files):")
        for path in missing:
            print(f"  {path}")


def main() -> None:
    if not CATALOG_PATH.is_file():
        raise SystemExit(f"missing {CATALOG_PATH}")
    if not INIT_PATH.is_file():
        raise SystemExit(f"missing {INIT_PATH} (root token)")
    if not OIDC_PATH.is_file():
        raise SystemExit(f"missing {OIDC_PATH} (Google OAuth client id/secret)")
    catalog = load_yaml(CATALOG_PATH)
    validate_catalog(catalog)
    token = yaml_scalar(INIT_PATH, "root_token")
    client_id, client_secret = oidc_credentials(OIDC_PATH)
    values = load_kv_seed_values()
    bao = Bao(BAO_ADDR, token)
    health = bao.request("GET", "sys/health")
    if health.get("sealed"):
        raise SystemExit("OpenBao is sealed; run task deploy-openbao first")
    ensure_mounts(bao, catalog)
    accessor = configure_oidc(bao, catalog, client_id, client_secret)
    write_policies(bao, catalog)
    sync_identity(bao, catalog, accessor)
    seed_kv(bao, catalog, values)
    print(f"ACL apply complete. UI login: {oidc_display_name(catalog)}")


if __name__ == "__main__":
    main()
