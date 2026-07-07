# Installation Guide for Solr Operator v0.9.1

## Install the CRDs (Custom Resource Definitions)

   ```bash
   kubectl create -f https://solr.apache.org/operator/downloads/crds/v0.9.1/all-with-dependencies.yaml
   ```

## Install the Solr Operator via Helm

   ```bash
   # Add helm repo for apahce-solr
   helm repo add apache-solr https://solr.apache.org/charts
   helm repo update

   # Installing solr-operator in a namespace
   helm install solr-operator apache-solr/solr-operator --version 0.9.1 --namespace solr-operator --create-namespace
   ```

## Verify the Installation

   ```bash
   kubectl get all
   ```

## Deploying a SolrCloud

Helm **release name** must be `{app}-{environment}` (e.g. `gxa-staging`). The **namespace** is
`{app}-{environment}-solrcloud`. Do not use bare `gxa` as the release — that collides across
environments (ZK PV names, service DNS) and breaks the GXA webapp Solr URLs.

With [Task](https://taskfile.dev/) (from repo root; set `K8S_CONTEXT` in `.env`). The target
namespace must already exist (e.g. `gxa-staging-solrcloud`); `task deploy-solrcloud` does not
create namespaces (requires cluster-admin).

   ```bash
   task deploy-solrcloud ENV=staging
   # Helm 4 + solr-operator SSA conflicts:
   FORCE_CONFLICTS=1 task deploy-solrcloud ENV=staging
   ```

Equivalent raw Helm:

   ```bash
   ENV=staging
   APP=gxa
   RELEASE=${APP}-${ENV}
   NS=${APP}-${ENV}-solrcloud

   kubectl create namespace ${NS} --dry-run=client -o yaml | kubectl apply -f -

   helm upgrade --install ${RELEASE} charts/solr-cloud \
         --namespace ${NS} \
         --values charts/solr-cloud/values-${ENV}.yaml \
         --create-namespace=false
   ```

   Get the Solr admin password (created automatically by the operator):

   ```bash
   kubectl get secret ${RELEASE}-solrcloud-security-bootstrap -o jsonpath='{.data.admin}' -n ${NS} | base64 --decode;echo
   ```

   Resulting names (example `ENV=staging`):

   | Kind | Name |
   |------|------|
   | Namespace | `gxa-staging-solrcloud` |
   | Helm release / SolrCloud CR | `gxa-staging` |
   | Solr pods | `gxa-staging-solrcloud-0` … |
   | ZK pods | `gxa-staging-solrcloud-zookeeper-0` … |
   | Solr service | `gxa-staging-solrcloud-common` |
   | NodePort | `gxa-staging-solrcloud-nodeport` |
   | ZK PVs | `gxa-staging-zk-data-0` … |

### ZooKeeper PVC stuck Pending

ZK uses static NFS PVs (`zookeeper.storage.nfsData.mode: pv`). Helm must create
`data-{release}-solrcloud-zookeeper-{n}` PVCs with `volumeName` set **before** the Solr
operator's StatefulSet creates them. If the operator wins the race, PVCs stay Pending
(no `volumeName`, no storage class) while the NFS PVs remain Available.

Fix:

```bash
task fix-solrcloud-zk-pvcs ENV=staging
kubectl delete pod -n gxa-staging-solrcloud -l app=gxa-staging-solrcloud-zookeeper
```

`task deploy-solrcloud` applies PV/PVC manifests before the full chart upgrade to avoid this.

### Recovering from release name `gxa` (wrong)

If SolrCloud was ever installed with release `gxa` instead of `gxa-${ENV}`, remove that
release **only if it still exists**, then install the correct one. **Keep** existing
`gxa-${ENV}-zk-data-*` PVs and `data-gxa-${ENV}-solrcloud-zookeeper-*` PVCs if present.

```bash
# Skip uninstall if the wrong release is already gone:
helm list -n gxa-staging-solrcloud | grep -w gxa && \
  helm uninstall gxa -n gxa-staging-solrcloud

FORCE_CONFLICTS=1 task deploy-solrcloud ENV=staging
task deploy ENV=staging   # GXA webapp — picks up gxa-staging-solrcloud-* service DNS
```

## NFS migration storage

With `solr.storage.nfsData.enabled` and `zookeeper.storage.nfsData.enabled` (default in
`values.yaml`), migrated data is read from Isilon exports under
`/ifs/public/rw/fg/atlas/gxa/environments/<environment>/{solr_data,zk_data}/<pod-name>/`.

### Write access required

Solr indexes through symlinks into `solr_data` (new experiments, analytics updates, etc.).
ZooKeeper writes `version-2` transaction logs under `zk_data`. **Both exports must be writable
from Kubernetes node IPs**, not only from codon/VM clients.

From a pod, `mount` may show `(rw)` while `touch` on the export returns `Read-only file system`
— that means the Isilon export ACL does not grant write to the cluster yet. Until that is fixed,
Solr can read migrated cores via symlinks but cannot index new data; ZK cannot run with pv mode.

**At migration scale (~1TB Solr index), copying into cluster NFS (`standard-nfs-production`) is
not practical.** Solr must stay on Isilon via symlinks (pod mode) — there is no copy-based
workaround for the index. The required fix is **Isilon export ACL: grant read-write to Kubernetes
node IPs/subnets** on both `solr_data` and `zk_data` under the environment path.

ZK data is small (MB); a one-time copy to ephemeral `/data` is a possible interim workaround
only for ZK while waiting for ACL — not for Solr.

**Default (`nfsData.mode: pod`)** — NFS is declared on the SolrCloud / Zookeeper pod spec
(same pattern as gxa `services-volume` and the Solr backup mount). The parent export is
mounted once per pod (Solr and ZK containers keep the NFS mount so symlinks resolve). Init
containers **symlink** each entry from the resolved `<pod-name>/` folder into `/var/solr/data`
(Solr) or `/data` (ZK) on first start — no data copy. The Solr link init runs **after**
`cp-solr-xml` (which creates a placeholder `solr.xml`); linking is gated on `.nfs-seeded`,
not on `solr.xml` being absent. Per-pod NFS entries are often symlinks (e.g.
`gxa-staging-solrcloud-0` → `0/solrdata.<timestamp>`); the init resolves the pod folder with
`readlink -f`, then `ln -sfn` each top-level entry into the operator data path.

To force re-linking from NFS, delete Solr/ZK pods (and their ephemeral data volumes).

**Zookeeper (`zookeeper.storage.nfsData.mode: pv`)** — default. Static NFS PVs + pre-bound PVCs
per replica mount migrated data directly at `/data` (ZK must write `version-2`; symlinks into
ephemeral `/data` do not work).

**Solr (`solr.storage.nfsData.mode: pod`)** — parent export mounted at `/solr-data`, init
symlinks cores into `/var/solr/data`.

**Alternative (`nfsData.mode: pv` for Solr too)** — only if pod-mode NFS fails on your cluster.

After switching from PV mode, delete old migration PVs/PVCs before reinstalling:

```bash
APP=gxa
ENV=staging
RELEASE=${APP}-${ENV}
NS=${APP}-${ENV}-solrcloud
kubectl delete solrcloud ${RELEASE} -n ${NS}
kubectl delete pvc -n ${NS} -l app.kubernetes.io/instance=${RELEASE}
kubectl delete pv ${RELEASE}-solr-data-{0,1,2,3} ${RELEASE}-zk-data-{0,1,2} 2>/dev/null || true
helm upgrade --install ${RELEASE} charts/solr-cloud --namespace ${NS} --set environment=${ENV}
```

Verify pod NFS mounts:

```bash
kubectl describe pod ${RELEASE}-solrcloud-0 -n ${NS} | grep -A3 'solr-data-nfs\|zk-data-nfs'
```

### NFS permissions

Isilon data is owned by `fg_atlas` (`runAsUser: 2921`, `runAsGroup: 1146`), matching the gxa
chart. With NFS `root_squash`, init containers running as root cannot read the export — the
`nfsSecurityContext` is applied to the NFS link init containers only. Solr/ZK runtime pods use
`fsGroup` and `supplementalGroups: [1146]` so the main containers can read NFS-backed symlinks
without overriding the Solr/ZK image users.

### Symlinks under `<pod-name>/`

Symlinks are supported (e.g. `gxa-staging-solrcloud-0 -> 0/solrdata...`). Do **not** use
Kubernetes `subPath` for them — mount the parent `solr_data/` or `zk_data/` export and
resolve paths by pod name instead.

If PVCs still show `storageClassName: standard-nfs-production`, the cluster was deployed
before NFS mode or old PVCs were retained. Delete the SolrCloud and its data PVCs, then
reinstall (pvcTemplate cannot change on an existing StatefulSet).
