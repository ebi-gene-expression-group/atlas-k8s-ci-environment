# Backstage (spike)

Spike deploy of the community Backstage Helm chart onto **fg-public**
(`hh-wp-webadmin-35`), namespace `backstage`. Demo image + guest auth — not a
production IdP or catalog ownership model.

## Prerequisites

```bash
helm repo add backstage https://backstage.github.io/charts
helm repo update
kubectl --context fg-public create namespace backstage --dry-run=client -o yaml \
  | kubectl --context fg-public apply -f -
```

Postgres passwords live in Secret `backstage-postgresql` (not committed). Create
or keep that secret before the first install; annotate it so Helm does not
recreate it on upgrade:

```bash
kubectl --context fg-public -n backstage annotate secret backstage-postgresql \
  helm.sh/resource-policy=keep --overwrite
```

## Install / upgrade

From the `atlas-k8s-ci-environment` repo root. Catalog files are mounted from a
ConfigMap (the upstream chart only loads Helm `appConfig`, so local YAML must be
applied separately):

```bash
kubectl --context fg-public -n backstage create configmap backstage-gxa-catalog \
  --from-file=gxa-entities.yaml=charts/backstage/catalog/gxa-entities.yaml \
  --from-file=annotare-entities.yaml=charts/backstage/catalog/annotare-entities.yaml \
  --dry-run=client -o yaml \
  | kubectl --context fg-public apply -f -

helm upgrade --install backstage backstage/backstage --version 2.8.2 \
  --kube-context fg-public \
  -n backstage \
  -f charts/backstage/values-spike.yaml \
  --timeout 10m \
  --wait
```

## Access

- Service: NodePort **30707** (nginx sidecar strips HSTS, proxies to Backstage `:7007`)
- URL: http://hh-rke-wp-webadmin-35-worker-1.caas.ebi.ac.uk:30707
- Sign in: **Guest → Enter**

Image is pinned to `ghcr.io/backstage/backstage:1.41.1` (see comments in
`values-spike.yaml`).

## Catalog

Catalog YAML under `catalog/` is mounted from ConfigMap `backstage-gxa-catalog`
(keys = filenames). Locations in `values-spike.yaml` load:

- `gxa-entities.yaml` — Gene Expression Atlas
- `annotare-entities.yaml` — Annotare (staging/public, MySQL, NFS, pipelines)

DB **passwords are not** in catalog files (host/user/db only; secrets in OpenBao).

After editing catalog files:

```bash
kubectl --context fg-public -n backstage create configmap backstage-gxa-catalog \
  --from-file=gxa-entities.yaml=charts/backstage/catalog/gxa-entities.yaml \
  --from-file=annotare-entities.yaml=charts/backstage/catalog/annotare-entities.yaml \
  --dry-run=client -o yaml \
  | kubectl --context fg-public apply -f -
kubectl --context fg-public -n backstage rollout restart deploy/backstage
```
