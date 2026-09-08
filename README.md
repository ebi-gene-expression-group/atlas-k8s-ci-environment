# K8S Configuration for Atlas Apps

*NOTE:* This is still work in progress.

This repo contains k8s files for Gene Expressions Atlas and Single Cell Expression Atlas on k8s.

## Helm Chart Structure

This repository uses Helm to manage Kubernetes manifests for the GXA and SCXA applications, with a shared chart for bioentity-properties.

### Structure

```text
charts/
  gxa/                  # Helm chart for GXA
  scxa/                 # TBA: Helm chart for SCXA
  solr-cloud            # TBA: solr cloud stuff
```

Other directories are the legacy k8s files that would be reorganised into helm charts.

### Usage

To install the GXA chart:

Create a `.dockerconfig.json` file with content:

```json
{
  "auths": {
    "dockerhub.ebi.ac.uk": {
      "username": "...",
      "password": "..."
    }
  }
}
```

This file will not be saved to git, as it is included in the `.gitignore`
The username and password are of the access token with `read_registry` scope you create in gitlab [group](https://gitlab.ebi.ac.uk/groups/ebi-gene-expression/-/settings/access_tokens) or project’s access tokens page.
Helm will create a `ServiceAccount` that defines an `imagePullSecret`  using which pods can access the docker image repository on gitlab. We need this because dockerhub has rate limitation, and we get many “too many requests” errors.

### Developer tasks (Task)

This repo includes a [`Taskfile.yml`](Taskfile.yml) using [Task](https://taskfile.dev/) so common commands are named, documented, and easy to discover. Install the [Task CLI](https://taskfile.dev/installation/), then:

- **`task`** or **`task --list`** — list all tasks with short descriptions (good starting point for new contributors).
- **`task test-system ENV=staging`** — live Tavern JSON journey (`/json/health`, experiments, search, gene). Or set `GXA_SYSTEM_BASE`. Jenkins job `gxa-json-system` uses `Jenkinsfile.system-test`.
- **`task deploy ENV=test`** — deploy the GXA/SCXA webapp chart.
- **`task deploy-solrcloud ENV=staging`** — deploy SolrCloud (`charts/solr-cloud/README.md`).

Other useful examples: `task deploy-test`, `task open-solr ENV=staging`, `task print-env`, `task mongodb-install ENV=test`. Set `K8S_CONTEXT` (and optionally `RELEASE`, `ENV`) in your environment or a `.env` file at the repo root (see `.env.example`).

**GXA indexing gap / Jenkins loads:** set `GXA_SOURCE_JSON_URL` (production catalogue) and `GXA_TARGET_JSON_URL` (deployment under test) in `.env`. Jenkins `TARGET_ENVIRONMENT` (e.g. `k8s_test`) must match that target — see `config/gxa-environments.yaml`. Then `task gxa-print-urls`, `task gxa-experiments-gap COUNT=10`, and `task trigger-indexing ACCESSIONS="..."`.

**Bioentities (new species on k8s):** `task bioentities-jenkins-params`, `task gxa-prod-only-species COUNT=10`, `task trigger-bioentities SPECIES=zea_mays`, or `task trigger-bioentities-top COUNT=2` (top prod-only species with a valid Jenkins `SPECIES` slug; default `PREFIX=build_work`).

### Configuration

- customize deployments by editing the respective `values-<env>.yaml` files
- passowrds (jdbc, tomcat deployer, etc.) can be configured in `.secrets-<env>.yaml`

### Adding a new deploy environment

Use a short environment name (e.g. `ci`, `staging`, `prod`). The Helm release deploys to namespace **`gxa-<env>`** (e.g. `gxa-ci`). SolrCloud, if used, lives in **`gxa-<env>-solrcloud`**.

Scaffold chart values locally first:

```bash
scripts/create-env.sh <env>          # creates charts/gxa/values-<env>.yaml
# edit charts/gxa/values-<env>.yaml and charts/gxa/.secrets-<env>.yaml (gitignored)
```

Then complete these four Jenkins / cluster steps before deploying from the pipeline.

#### 1. DevOps Portal environment

The deploy pipeline records deployments via `reportDeployOperation`. The `targetService` must match an environment label in **Jenkins → DevOps Portal → Manage Environments**.

For GXA, the label is **`gxa-<env>`** (same as the Kubernetes namespace), e.g. `gxa-ci`, `gxa-staging`.

Add that label in DevOps Portal before the first non–dry-run deploy to the new environment.

#### 2. Jenkins secrets credential

The pipeline loads secrets with credential id **`gxa-secrets-<env>`** (see `Jenkinsfile`).

In Jenkins (**Manage Credentials**), create a **Secret file** credential:

| Field | Value |
| --- | --- |
| ID | `gxa-secrets-<env>` (e.g. `gxa-secrets-ci`) |
| File | YAML with the same structure as `charts/gxa/.secrets-<env>.yaml` |

Typical keys (set only what the values file needs):

```yaml
postgresql:
  superuserPassword: "..."
  atlasprd3Password: "..."
  atlasdataloadPassword: "..."
  populate:
    source:
      password: "..."   # if using postgresql.populate
jdbc:
  password: "..."
solr:
  password: "..."
tomcat:
  deployerPassword: "..."
  curatorPassword: "..."
imagePullSecret:
  create: yes
  username: "..."
  password: "..."
```

Copy from an existing environment’s local `.secrets-*.yaml` as a template. Do not commit secrets to git.

#### 3. Jenkinsfile parameter

Add the new name to the `ENV` choice list in [`Jenkinsfile`](Jenkinsfile):

```groovy
choice(
  name: 'ENV',
  choices: [
    'ci',
    'staging',
    '<env>',   // add here
    'prod',
  ],
  ...
)
```

Push the change, then run **Build Now** once on the pipeline job so Jenkins refreshes the parameter list (the UI caches the previous definition until a build runs).

The pipeline also requires `charts/gxa/values-<env>.yaml` to exist; it fails validation if missing.

The agent pod is scheduled on Jenkins Kubernetes cloud **`hh-webadmin-35`**, except **`ENV=fallback`**, which uses **`hx-webadmin-121`**. Both clouds need namespace `gxa-jenkins` and the `jenkins-cloud` service account (see step 4).

#### 4. Kubernetes deploy Role

Jenkins deploys as service account **`jenkins-cloud`** in namespace **`gxa-jenkins`**. It needs a **Role** and **RoleBinding** in the target namespace **`gxa-<env>`**.

Copy the `jenkins-gxa-deploy` Role + RoleBinding block for an existing environment in [`jenkins/fg-public-agent-rbac.yaml`](jenkins/fg-public-agent-rbac.yaml) (see `gxa-staging` or `gxa-ci`), change the namespace and `atlas.ebi.ac.uk/target-namespace` label to `gxa-<env>`, then apply:

```bash
kubectl --context=fg-public apply -f jenkins/fg-public-agent-rbac.yaml
```

Verify:

```bash
kubectl get role,rolebinding -n gxa-<env> -l atlas.ebi.ac.uk/jenkins-role=deploy
```

If you deploy SolrCloud to Jenkins as well, repeat the same Role/RoleBinding pattern in **`gxa-<env>-solrcloud`** (or create that namespace and RBAC before `task deploy-solrcloud`).

Ensure namespace **`gxa-<env>`** exists (the pipeline uses `helm upgrade --install ... --create-namespace`, but namespace creation may require cluster-admin; creating the namespace ahead of time avoids that).
