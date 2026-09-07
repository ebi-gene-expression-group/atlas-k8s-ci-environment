# Installation Guide for Solr Operator v0.9.1

## Install the CRDs (Custom Resource Definitions)

## Install the Solr Operator via Helm

## Verify the Installation

## Team RBAC for SolrCloud CRs

Installing the operator and CRDs is not enough. Helm must **get/create/update**
`solrclouds.solr.apache.org`. CRDs being listed (`kubectl api-resources | grep solr`)
does **not** mean you can use them.

On fg-public this is **cluster-wide** (a ClusterRole on `team-admin`), not a
per-namespace Role — `auth can-i` is `yes` in every namespace. You do not set
this per SolrCloud namespace.

Check (expect `yes`):

```bash
kubectl auth can-i '*' solrclouds --all-namespaces
```

`no` is the Helm error `cannot get resource "solrclouds"`. `team-admin` cannot
create ClusterRoles; ITS must grant this after installing the operator.

Ask ITS to apply this ClusterRole + ClusterRoleBinding (same scope as fg-public).
Subject is the CaaS team SA `default:team-admin`. Alternatively, add the
`solr.apache.org` rules below to the team's existing ClusterRole:

```bash
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: solrcloud-admin
rules:
  - apiGroups: ["solr.apache.org"]
    resources: ["solrclouds", "solrbackups", "solrprometheusexporters"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: solrcloud-admin
subjects:
  - kind: ServiceAccount
    name: team-admin
    namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: solrcloud-admin
EOF
```

## Deploying a SolrCloud

Helm **release name** must be `{app}-{environment}` (e.g. `gxa-staging`). The **namespace** is
`{app}-{environment}-solrcloud`. Do not use bare `gxa` as the release — that collides across
environments (ZK PV names, service DNS) and breaks the GXA webapp Solr URLs.

With [Task](https://taskfile.dev/) (from repo root; set `K8S_CONTEXT` in `.env`). The target
namespace must already exist (e.g. `gxa-staging-solrcloud`); `task deploy-solrcloud` does not
create namespaces (requires cluster-admin).

Equivalent raw Helm:

   Get the Solr admin password (created automatically by the operator):

   Resulting names (example `ENV=staging`):


| Kind                        | Name                                  |
| --------------------------- | ------------------------------------- |
| Namespace                   | `gxa-staging-solrcloud`               |
| Helm release / SolrCloud CR | `gxa-staging`                         |
| Solr pods                   | `gxa-staging-solrcloud-0` …           |
| ZK pods                     | `gxa-staging-solrcloud-zookeeper-0` … |
| Solr service                | `gxa-staging-solrcloud-common`        |
| NodePort                    | `gxa-staging-solrcloud-nodeport`      |
| ZK PVs                      | `gxa-staging-zk-data-0` …             |


### Fallback cluster (`fg-fallback`)

Fallback SolrCloud runs on **hx-wp-webadmin-121**. Use context `fg-fallback` and `ENV=fallback`. The namespace `gxa-fallback-solrcloud` must already exist.

```bash
K8S_CONTEXT=fg-fallback ENV=fallback FORCE_CONFLICTS=1 task deploy-solrcloud
```

Equivalent raw Helm (`RELEASE=gxa-fallback`, `NS=gxa-fallback-solrcloud`):

```bash
ENV=fallback
APP=gxa
RELEASE=${APP}-${ENV}
NS=${APP}-${ENV}-solrcloud

helm upgrade --install ${RELEASE} charts/solr-cloud \
      --kube-context fg-fallback \
      --namespace ${NS} \
      --values charts/solr-cloud/values-${ENV}.yaml \
      --create-namespace=false \
      --force-conflicts
```

NFS is vlan157: `hx-isi-srv-vlan157.ebi.ac.uk:/ifs/public-r/rw/fg/atlas/gxa/environments/fallback/{solr_data,zk_data}/`. Solr folders are `gxa-solrcloud-{n}` (`dataDirPrefix: gxa` in `values-fallback.yaml`). ZK folders must be `gxa-fallback-solrcloud-zookeeper-{n}`. After rsync from Hinxton the tree still uses **staging** ZK names — rewrite before deploy (Codon, dest ZK stopped):

```bash
BASE=/nfs/ebi/public/rw/fg/atlas/gxa/environments SRC=staging DST=fallback \
  ./scripts/slurm/rewrite-gxa-zk-env-names.sh
```

Resulting names (`ENV=fallback`): namespace `gxa-fallback-solrcloud`, release/CR `gxa-fallback`, Solr service `gxa-fallback-solrcloud-common`, ZK PVs `gxa-fallback-zk-data-0` …

### ZooKeeper PVC stuck Pending

ZK always uses static NFS PVs. Helm must create
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

## NFS storage

Solr and ZooKeeper data are **always** the Isilon `{solr_data,zk_data}` folders.
There is no cluster PVC (`standard-nfs-production`) and no `nfsData.enabled` switch.

Paths:

`{nfs.publicPath}/{nfs.environmentsBase}/{environment}/{solr_data,zk_data}/`

Default: `/ifs/public/rw/fg/atlas/gxa/environments/<environment>/{solr_data,zk_data}/<pod-name>/`, and `/ifs/public-r` on the fallback site (HL2)

### Write access required

Solr indexes through symlinks into `solr_data` (new experiments, analytics updates, etc.).
ZooKeeper writes `version-2` transaction logs under `zk_data`. **Both exports must be writable
from Kubernetes node IPs**, not only from codon/VM clients.

From a pod, `mount` may show `(rw)` while `touch` on the export returns `Read-only file system`
— that means the Isilon export ACL does not grant write to the cluster yet. Until that is fixed,
Solr can read migrated cores via symlinks but cannot index new data, and ZK cannot persist
`version-2` logs. The required fix is **Isilon export ACL: grant read-write to Kubernetes
node IPs/subnets** on both `solr_data` and `zk_data` under the environment path.

**Solr** — NFS is declared on the SolrCloud pod spec (same pattern as gxa `services-volume`
and the Solr backup mount). The parent export is mounted once per pod so symlinks resolve.
The init container **symlinks** each entry from `{dataDirPrefix}-solrcloud-{n}/` into
`/var/solr/data` on first start — no data copy. It runs **after** `cp-solr-xml` (which
creates a placeholder `solr.xml`); linking is gated on `.nfs-seeded`, not on `solr.xml`
being absent. Per-pod NFS entries are often themselves symlinks (e.g.
`gxa-staging-solrcloud-0` → `0/solrdata.<timestamp>`); the init resolves the folder with
`readlink -f`, then `ln -sfn` each top-level entry.

To force re-linking from NFS, delete Solr pods (and their ephemeral data volumes).

**ZooKeeper** — static NFS PV + pre-bound PVC per replica, mounted at `/data`. ZK must write
`version-2` into the export; Solr-style symlinks into ephemeral `/data` do not work.

Verify Solr NFS mounts:

```bash
kubectl describe pod ${RELEASE}-solrcloud-0 -n ${NS} | grep -A3 solr-data-nfs
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