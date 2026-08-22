# OpenBao (fg-public)

Self-hosted [OpenBao](https://openbao.org/) on **fg-public** (`hh-wp-webadmin-35`),
namespace `openbao`. Standalone file storage on `standard-nfs-production` — not HA;
revisit Raft + auto-unseal if this becomes a production secrets store.

Uses the existing cluster ingress-nginx (class `nginx`).

The official chart declares `kubeVersion: ">= 1.30.0-0"`. fg-public is Kubernetes
**1.23.8**, so `task deploy-openbao` pulls the chart and relaxes that constraint
before install. The Agent Injector, CSI provider, and Kubernetes auth-delegator
are disabled: team-admin cannot create cluster-scoped webhooks or ClusterRoles.

## Access

- UI / API: https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk
- Health: https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk/v1/sys/health
- Human login: **EMBL-EBI Login** (Google OIDC, catalog email allowlist). Root token is for `task deploy-openbao` / `task openbao-apply-acl` only. The UI tab is the mount path `embl-ebi` (spaces are not allowed).

TLS is terminated in front of the cluster. Ingress stays HTTP.

Image is pinned to `quay.io/openbao/openbao:2.6.1` (see `values-public.yaml`).
The chart `appVersion` is `v2.6.1`; container tags do **not** use the `v` prefix.
Helm chart `openbao` **0.29.0**.

## Google Workspace OIDC

OAuth client lives in GCP project
[`prj-int-dev-atlas-app-intg`](https://console.cloud.google.com/auth/branding?project=prj-int-dev-atlas-app-intg)
(consent screen / branding). Client:
[`openbao fg client`](https://console.cloud.google.com/auth/clients/837544769791-uiiiurk404d83s208ebrk4gnnla71djr.apps.googleusercontent.com?project=prj-int-dev-atlas-app-intg).

Client id and secret: `charts/openbao/.secrets-oidc-public.yaml` (gitignored).

Redirect URIs on that client (must match OpenBao):

- `https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk/ui/vault/auth/embl-ebi/oidc/callback`
- `http://localhost:8250/oidc/callback`

Scopes are on the consent screen (**Google Auth platform → Data access**, or **OAuth consent screen → Add or remove scopes**): `openid`, `email`, `profile`.

fg-public pods cannot reach the internet directly. The OpenBao server must
fetch Google’s discovery document and exchange the OIDC code, so
`values-public.yaml` sets `HTTP_PROXY`/`HTTPS_PROXY` to
`http://hh-wwwcache.ebi.ac.uk:3128` (same as GXA). Without that, apply fails
with `error checking oidc discovery URL`.

Allowed users are emails in [`charts/openbao/acl/catalog.yaml`](acl/catalog.yaml), not everyone in the Workspace. A membership is `{ group, role }` (role applies to every service in that group) or `{ group, role, services: [gxa] }` to limit it. After editing the catalog:

```bash
task openbao-apply-acl
```

## Prerequisites

```bash
helm repo add openbao https://openbao.github.io/openbao-helm
helm repo update

# Namespace: create once with kubectl (team-admin can create but often cannot
# patch Namespace objects).
kubectl --context fg-public create namespace openbao --dry-run=client -o yaml \
  | kubectl --context fg-public apply -f -
```

## Install / upgrade

From the `atlas-k8s-ci-environment` repo root (always targets **fg-public**, even if
`.env` has `K8S_CONTEXT=fg-fallback-legacy`):

```bash
task deploy-openbao
```

The task installs/upgrades the release, then **initializes and unseals** if
needed. Unseal keys and the root token are written to
`charts/openbao/.secrets-init-public.yaml` (gitignored). Copy that file off the
laptop — without the keys you cannot unseal after a pod restart, even with the
PVC intact.

Pods stay unready until unsealed; do not pass Helm `--wait` unless the probe is
changed to treat sealed/uninitialized as success.

## Verify

```bash
kubectl --context fg-public -n openbao get pods,ingress,pvc
kubectl --context fg-public -n openbao exec openbao-0 -- bao status
curl -fsS https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk/v1/sys/health
```

## After a pod restart (sealed)

If `.secrets-init-public.yaml` exists locally:

```bash
task deploy-openbao
```

That waits for the replacement pod, then unseals from `.secrets-init-public.yaml`
(no interactive key prompt). Do not type Shamir shares into the UI unless that
file is missing.

Manual unseal:

```bash
kubectl --context fg-public -n openbao exec -ti openbao-0 -- bao operator unseal
```

## ACL catalog (groups, roles, KV paths)

Source of truth: [`acl/catalog.yaml`](acl/catalog.yaml). Paths are
`kv/data/<service>/<environment>/<class>/<secret>` for apps, or
`kv/data/<service>/<cluster-server>/<class>/<secret>` for cluster-scoped
items such as kubeconfigs. `cluster-server` is the kubeconfig API host
(no `https://` or port), e.g. `hh-wp-webadmin-35.wp-k8s.ebi.ac.uk`. `class`
is `app` (runtime) or `ops` (deploy/data-load/kubeconfig). Kubernetes
namespaces (`gxa-public`, …) live under `services.<id>.namespaces` (KV
custom_metadata), not in the path.
Seed values come from gitignored `charts/gxa/.secrets-<env>.yaml` (optional
override: `.secrets-kv-public.yaml`). GitLab pull secrets are not stored here.

```bash
task openbao-apply-acl
```

Requires OpenBao to be unsealed, plus `.secrets-init-public.yaml` and
`.secrets-oidc-public.yaml`.

## Enabling the Agent Injector later

Needs cluster-admin (MutatingWebhookConfiguration + ClusterRoleBinding). Set
`injector.enabled: true` and `server.authDelegator.enabled: true`, then
`task deploy-openbao`.
