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

### Web/REST

- UI / API: [https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk](https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk)
- Health: [https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk/v1/sys/health](https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk/v1/sys/health)
- Human login: **EMBL-EBI Login** (Google OIDC, catalog email allowlist). The UI and default `bao login` use OIDC role `google` (catalog KV grants only). Users with `openbao_admin: true` can also `bao login -method=oidc -path=embl-ebi role=admin` for identity/policies/AppRole (policy `openbao-admin`). Root token is for `task deploy-openbao` / `task openbao-apply-acl` only. The UI tab is the mount path `embl-ebi` (spaces are not allowed).

TLS is terminated in front of the cluster. Ingress stays HTTP.

### CLI

CLI is done using using the `bao` tool. Install using a [package manager](https://openbao.org/docs/install/#package-manager) or a [precompiled binary](https://openbao.org/downloads/)

On an interactive shell that allows opening a browser, use: 

  ```bash
  export BAO_ADDR='https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk'  
  # This is required until the TLS signature is properly configured on the EBI Traffic Manager
  export BAO_SKIP_VERIFY=true
  # this will open a browser with the Google login page (limited: catalog KV grants)
  bao login -method=oidc -path=embl-ebi
  # OpenBao admin (identity, policies, AppRole) — only users with openbao_admin: true
  bao login -method=oidc -path=embl-ebi role=admin
  # This gets a secret
  bao kv get -mount=kv -format yaml -field password annotare/public/app/jdbc-readonly
  ```

In a non-interactive shell, e.g. SLURM job:

1. admin will create a role with the requirement access policy and relevant ttl values

Catalog AppRoles (preferred): add an `approles:` entry in `acl/catalog.fg.yaml` (or another split catalog) and run `task openbao:apply-acl`. Example: `pipeline-fenix-zarr-export-dev` can read `kv/data/fenix/dev/*`. Then mint a secret id (not stored in git):

```bash
bao read auth/approle/role/pipeline-fenix-zarr-export-dev/role-id
bao write -f -field=secret_id auth/approle/role/pipeline-fenix-zarr-export-dev/secret-id
```

Ad-hoc AppRole (not in the catalog):

```bash
bao write auth/approle/role/fg-cli-dev \
    token_policies=group-fg-role-developer-annotare
```

1. admin will get the role id and a fresh secret

```bash
bao read auth/approle/role/fg-cli-dev/role-id
bao write -f -field=secret_id auth/approle/role/fg-cli-dev/secret-id
```

1. obtain role id and secret from the admin as a json file:

  ```json
  {
    "role_id": "your-role-id",
    "secret_id": "your-secret-id"
  }
  ```

1. save in a safe location e.g. $HOME/.config/bao/slurm-login.json" and protect with `chmod 600`.

1. obtain a token

  ```bash
  export BAO_TOKEN=$(bao write -field=token \
    auth/approle/login @"$HOME/.config/bao/slurm-login.json")
  ```

1. get a secret

```bash
bao kv get kv/annotare/test/app/jdbc
```

### Jenkins (Fenix pipelines)

Jenkins jobs should log in with AppRole and read KV at run time, not store S3 keys
in Jenkins. Store **role_id** / **secret_id** as a **Username with password**
credential in the folder that owns the job:

- ID: `pipeline-fenix-zarr-export-<ENV>` (e.g. `pipeline-fenix-zarr-export-dev`). Do not prefix with `openbao-`.
- Username: OpenBao `role_id`
- Password: OpenBao `secret_id` (mint once; do not remint every build)

`<ENV>` is the job build parameter. Dev AppRole `pipeline-fenix-zarr-export-dev`
can read `kv/data/fenix/dev/*`. Staging needs a matching AppRole
(`pipeline-fenix-zarr-export-staging`) before `ENV=staging` jobs can use this.

See [FG-642](https://embl.atlassian.net/browse/FG-642).

```groovy
def credId = "pipeline-fenix-zarr-export-${params.ENV}"

withCredentials([usernamePassword(
    credentialsId: credId,
    usernameVariable: 'BAO_ROLE_ID',
    passwordVariable: 'BAO_SECRET_ID'
)]) {
    sh """
      export BAO_ADDR=https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk
      export BAO_SKIP_VERIFY=true
      export BAO_TOKEN=\$(bao write -field=token auth/approle/login \\
        role_id="\$BAO_ROLE_ID" secret_id="\$BAO_SECRET_ID")
      bao kv get -mount=kv -format yaml \\
        fenix/${params.ENV}/ebi-storage/fenix-data-${params.ENV}/ReadOnly
    """
}
```

Notes:

- `credentialsId` is Groovy (`${params.ENV}` expands before `sh`).
- Inside the Groovy GString (`"""`), escape shell dollars as `\$` so Jenkins does not interpolate `BAO_ROLE_ID`.
- The agent image needs the `bao` CLI. `BAO_SKIP_VERIFY=true` until Traffic Manager TLS is correct.
- Use `.../ReadWrite` instead of `.../ReadOnly` if the job must write to the bucket.

### GitLab CI (Fenix pipelines)

Same AppRole as Jenkins: store **role_id** / **secret_id** as CI/CD variables, not S3 keys.

Group variables — [ebi-gene-expression](https://gitlab.ebi.ac.uk/groups/ebi-gene-expression/-/settings/ci_cd),
**Settings → CI/CD → Variables**, all environments:

- `BAO_ADDR` — `https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk`
- `BAO_SKIP_VERIFY` — `true` until Traffic Manager TLS is correct

Per environment (project or group), masked:

- `BAO_ROLE_ID` — OpenBao `role_id`. Environment scope `dev`.
- `BAO_SECRET_ID` — OpenBao `secret_id` (mint once; hidden if the UI offers it). Environment scope `dev`.

Repeat the AppRole pair with environment scope `staging` when AppRole
`pipeline-fenix-zarr-export-staging` exists. The job must set `environment: name:`
to that env (or `$ENV`) so GitLab injects the matching pair.
Protect the AppRole variables if the job only runs on protected branches.

```yaml
fenix-zarr-export:
  environment:
    name: $ENV
  script:
    - |
      export BAO_TOKEN=$(bao write -field=token auth/approle/login \
        role_id="$BAO_ROLE_ID" secret_id="$BAO_SECRET_ID")
      bao kv get -mount=kv -format yaml \
        fenix/${ENV}/ebi-storage/fenix-data-${ENV}/ReadOnly
```

Notes:

- Pass `ENV` as a pipeline variable (`dev` today). The runner image needs the `bao` CLI.
- Use `.../ReadWrite` instead of `.../ReadOnly` if the job must write to the bucket.

## App version & Helm Chart

Image is pinned to `quay.io/openbao/openbao:2.6.1` (see `values-public.yaml`).
The chart `appVersion` is `v2.6.1`; container tags do **not** use the `v` prefix.
Helm chart `openbao` **0.29.0**.

## Google Workspace OIDC

OAuth client lives in GCP project [prj-int-dev-atlas-app-intg](https://console.cloud.google.com/auth/branding?project=prj-int-dev-atlas-app-intg)
(consent screen / branding). Client: [openbao fg client](https://console.cloud.google.com/auth/clients/837544769791-uiiiurk404d83s208ebrk4gnnla71djr.apps.googleusercontent.com?project=prj-int-dev-atlas-app-intg).

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

Allowed users are emails in `[charts/openbao/acl/catalog.yaml](acl/catalog.yaml)`, not everyone in the Workspace. A membership is `{ group, role }` (role applies to every service in that group) or `{ group, role, services: [gxa] }` to limit it. After editing the catalog:

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
`charts/openbao/.secrets-init-public.yaml` (gitignored). The durable copy is
in Secret Manager; see [Unseal keys and root token](#unseal-keys-and-root-token).
Without the keys you cannot unseal after a pod restart, even with the PVC intact.

Pods stay unready until unsealed; do not pass Helm `--wait` unless the probe is
changed to treat sealed/uninitialized as success.

## Verify

```bash
kubectl --context fg-public -n openbao get pods,ingress,pvc
kubectl --context fg-public -n openbao exec openbao-0 -- bao status
curl -fsS https://openbao.hh-webadmin-35.wp-k8s.ebi.ac.uk/v1/sys/health
```



## Unseal keys and root token

Shamir threshold is 3 of 5. `task deploy-openbao` and `task openbao-apply-acl`
read the gitignored working copy `charts/openbao/.secrets-init-public.yaml`.
The durable copy is GCP Secret Manager in project
[prj-int-dev-func-gen-webst](https://console.cloud.google.com/security/secret-manager?project=prj-int-dev-func-gen-webst):

| Secret | Contents |
| --- | --- |
| `openbao-fg-public-unseal-1` … `openbao-fg-public-unseal-5` | one Shamir share each |
| `openbao-fg-public-root-token` | root token |

Each share is its own secret so access can be split across people. Anyone with
Owner or Secret Manager Admin on that project can still read all six. A new
`bao operator init` replaces every value: add a new secret version and destroy
the previous one.

Rebuild the local file from Secret Manager:

```bash
PROJECT=prj-int-dev-func-gen-webst
OUT=charts/openbao/.secrets-init-public.yaml
{
  echo "# Never commit. Durable copy is in Secret Manager ($PROJECT)."
  echo "unseal_threshold: 3"
  printf 'root_token: "%s"\n' \
    "$(gcloud secrets versions access latest --secret=openbao-fg-public-root-token --project="$PROJECT")"
  echo "unseal_keys_b64:"
  for i in 1 2 3 4 5; do
    printf '  - "%s"\n' \
      "$(gcloud secrets versions access latest --secret=openbao-fg-public-unseal-$i --project="$PROJECT")"
  done
} > "$OUT"
chmod 600 "$OUT"
```

## After a pod restart (sealed)

If `.secrets-init-public.yaml` exists locally:

```bash
task deploy-openbao
```

That waits for the replacement pod, then unseals from `.secrets-init-public.yaml`
(no interactive key prompt). If the file is missing, rebuild it from Secret
Manager above, then run the task again.

Manual unseal:

```bash
kubectl --context fg-public -n openbao exec -ti openbao-0 -- bao operator unseal
```



## ACL catalog (groups, roles, KV paths)

Source of truth: `[acl/catalog.yaml](acl/catalog.yaml)`. Paths are
`kv/data/<service>/<environment>/<class>/<secret>` for apps,
`kv/data/<service>/<cluster-server>/<class>/<secret>` for cluster-scoped
items such as kubeconfigs, or `kv/data/<service>/<environment>/<secret>` for
class-less secrets (e.g. `fenix/dev/ebi-storage`). `cluster-server` is the kubeconfig API host
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