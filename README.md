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
- **`task deploy ENV=test`** — deploy the app chart (same idea as `ENV=test make deploy` below).

Other useful examples: `task deploy-test`, `task print-env`, `task mongodb-install ENV=test`. Set `K8S_CONTEXT` (and optionally `RELEASE`, `ENV`) in your environment or a `.env` file at the repo root.

You can still use **Make** for the same workflows; see the `Makefile` (e.g. `ENV=test make deploy`).

```sh
ENV=test make deploy
```

### Configuration

- customize deployments by editing the respective `values-<env>.yaml` files
- passowrds (jdbc, tomcat deployer, etc.) can be configured in `.secrets-<env>.yaml`
