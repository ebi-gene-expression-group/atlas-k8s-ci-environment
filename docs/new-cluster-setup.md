# New Kubernetes cluster setup (GXA)

Use this when GXA moves to a **new CaaS cluster** (example: fallback on `hx-wp-webadmin-121` / kubectl context `fg-fallback`). Adding another environment on an **existing** cluster (`ci` / `staging` / `public` on `hh-wp-webadmin-35`) is [README — Adding a new deploy environment](../README.md#adding-a-new-deploy-environment).

Recommended order (Solr NFS must exist before the SolrCloud chart):

1. [Solr CRDs and operator](#1-solr-crds-and-operator)
2. [Solr data directory (NFS)](#2-solr-data-directory-nfs)
3. [SolrCloud chart](#3-solrcloud-chart)
4. [PostgreSQL firewall](#4-postgresql-firewall)
5. [GXA webapp Helm chart](#5-gxa-webapp-helm-chart)
6. [Jenkins Kubernetes cloud and deploy Role](#6-jenkins-kubernetes-cloud-and-deploy-role)
7. [Jenkins secrets credential](#7-jenkins-secrets-credential)

Placeholders: `<env>` (e.g. `fallback`), `<context>` (e.g. `fg-fallback`), Jenkins cloud name (e.g. `hx-webadmin-121`). Helm release for SolrCloud is `gxa-<env>`; webapp release is `gxa` in namespace `gxa-<env>`.

`team-admin` cannot create namespaces or ClusterRoles. Ask ITS for those.

## Prerequisites

- kubectl context for the new cluster (store in `.env` as `K8S_CONTEXT`).
- ITS-created namespaces:
  - `gxa-jenkins` (Jenkins agent pods)
  - `gxa-<env>` (webapp)
  - `gxa-<env>-solrcloud` (Solr + ZooKeeper)
- Isilon NFS reachable from **worker node IPs** (read-write on `{solr_data,zk_data}`; see [NFS storage](../charts/solr-cloud/README.md#nfs-storage)). Fallback uses `hx-isi-srv-vlan157.ebi.ac.uk` and `/ifs/public-r` ([KB0011170](https://embl.service-now.com/esc?id=kb_article&sysparm_article=KB0011170)).
- Chart values: `charts/gxa/values-<env>.yaml` and `charts/solr-cloud/values-<env>.yaml` (NFS server, `jdbc.url`, `solr.namespace`).

## 1. Solr CRDs and operator

Install **Solr Operator v0.9.1** once per cluster (CRDs are cluster-scoped). Needs cluster-admin.

```bash
kubectl --context <context> create -f \
  https://solr.apache.org/operator/downloads/crds/v0.9.1/all-with-dependencies.yaml

helm repo add apache-solr https://solr.apache.org/charts
helm repo update apache-solr

helm upgrade --install solr-operator apache-solr/solr-operator \
  --version 0.9.1 \
  --kube-context <context> \
  --namespace solr-operator \
  --create-namespace
```

`all-with-dependencies.yaml` includes the ZooKeeper operator CRDs. Helm alone does not.

Verify:

```bash
kubectl --context <context> api-resources | grep solr
kubectl --context <context> -n solr-operator get deploy,pods
```

Then ITS must grant `team-admin` access to `solrclouds.solr.apache.org`. Listing CRDs is not enough. Helm error `cannot get resource "solrclouds"` means this step is missing.

```bash
kubectl --context <context> auth can-i '*' solrclouds --all-namespaces
```

Expect `yes`. ClusterRole + ClusterRoleBinding to apply: [charts/solr-cloud/README.md — Team RBAC](../charts/solr-cloud/README.md#team-rbac-for-solrcloud-crs).

## 2. Solr data directory (NFS)

Solr and ZooKeeper **always** use Isilon folders, not cluster PVCs.

Path:

`{nfs.publicPath}/{nfs.environmentsBase}/<env>/{solr_data,zk_data}/`

Example (Hinxton public): `/ifs/public/rw/fg/atlas/gxa/environments/<env>/{solr_data,zk_data}/`  
Example (fallback / HL2): `/ifs/public-r/rw/fg/atlas/gxa/environments/fallback/{solr_data,zk_data}/`

Layout the chart expects:

| Path under the env dir | Folder names |
| --- | --- |
| `solr_data/` | `{dataDirPrefix}-solrcloud-{0..3}` (default prefix = Helm release `gxa-<env>`; override in values, e.g. `dataDirPrefix: gxa`) |
| `zk_data/` | `{release}-solrcloud-zookeeper-{0..2}` (must match the SolrCloud release, e.g. `gxa-fallback-solrcloud-zookeeper-0`) |

Copy from another env with a Codon **datamover** job (login nodes often do not mount `/nfs/public`). Scripts: [`scripts/slurm/README.md`](../scripts/slurm/README.md).

After rsync, ZooKeeper directories and `zoo.cfg*` often still name the **source** env. Rewrite **before** deploy, with destination ZK stopped:

```bash
BASE=/nfs/ebi/public/rw/fg/atlas/gxa/environments SRC=staging DST=fallback \
  ./scripts/slurm/rewrite-gxa-zk-env-names.sh
```

Confirm from a probe pod that the export is **writable** from this cluster (`touch` must succeed; `mount` showing `(rw)` is not enough). Ownership is `fg_atlas` (`uid 2921` / `gid 1146`).

## 3. SolrCloud chart

```bash
K8S_CONTEXT=<context> ENV=<env> FORCE_CONFLICTS=1 task deploy-solrcloud
```

`task deploy-solrcloud` applies ZK NFS PV/PVCs **before** the operator creates StatefulSets (avoids Pending PVCs). It does **not** create the namespace.

Wait until 4 Solr + 3 ZK pods are Ready. Copy the operator-generated admin password into the webapp secrets (gitignored; also Jenkins in step 7):

```bash
kubectl --context <context> -n gxa-<env>-solrcloud \
  get secret gxa-<env>-solrcloud-security-bootstrap \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Put that value in `charts/gxa/.secrets-<env>.yaml` under `solr.password`. Details and recovery: [charts/solr-cloud/README.md](../charts/solr-cloud/README.md).

## 4. PostgreSQL firewall

The webapp uses an **external** Postgres (`jdbc.url` in `charts/gxa/values-<env>.yaml`), not in-cluster PG. Cluster **worker / pod networks** must be allowed to that host:5432.

Ask ITS (firewall / DB ACL). Include:

- JDBC host, port, database, and role from `values-<env>.yaml` / [`config/gxa-environments.yaml`](../config/gxa-environments.yaml)
- New cluster worker node CIDRs (and pod CIDR if different from workers)

Check TCP from a pod in `gxa-<env>` (chart test `templates/tests/test-jdbc.yaml`):

```bash
helm test gxa -n gxa-<env> --kube-context <context> --filter name=gxa-test-jdbc
# or: kubectl run ... --image=busybox -- nc -z -w 5 <pg-host> 5432
```

`connection refused` / timeout is firewall. `database does not exist` is the DB name/role, not the firewall.

## 5. GXA webapp Helm chart

Local first (`.env`: `K8S_CONTEXT`, `RELEASE=gxa`, `ENV=<env>`):

```bash
task deploy
```

Equivalent:

```bash
helm upgrade --install gxa charts/gxa \
  --kube-context <context> \
  --namespace gxa-<env> \
  --create-namespace \
  -f charts/gxa/values-<env>.yaml \
  -f charts/gxa/.secrets-<env>.yaml \
  --set appVersion=<image-tag> \
  --set image.tag=<image-tag>
```

`--create-namespace` fails if `team-admin` cannot create namespaces — create `gxa-<env>` with ITS first.

The first Ready gate is `/gxa/json/experiments` (experiment cache from the DB). Startup/liveness stay on `/gxa/json/health`. Chart details: [charts/gxa/readme.md](../charts/gxa/readme.md).

## 6. Jenkins Kubernetes cloud and deploy Role

The deploy pipeline (`Jenkinsfile`) runs Helm **inside** an agent pod on the **target** cluster. `ENV=fallback` uses Jenkins Kubernetes cloud `hx-webadmin-121`; other envs use `hh-webadmin-35`. A new cluster needs a matching cloud name (add it to the `Jenkinsfile` ternary).

### Agent namespace (once per cluster)

On the new cluster, apply the `gxa-jenkins` Namespace, `jenkins-cloud` ServiceAccount, `jenkins-agent-pods` Role, and RoleBinding from [`jenkins/fg-public-agent-rbac.yaml`](../jenkins/fg-public-agent-rbac.yaml) (copy the file, retarget labels/context). Point the Jenkins Kubernetes plugin at that kubeconfig. Agent pod spec: [`jenkins-k8s-pod-deploy.yaml`](../jenkins-k8s-pod-deploy.yaml) (`namespace: gxa-jenkins`, `serviceAccountName: jenkins-cloud`).

### Deploy Role (once per target namespace)

Helm lists **Secrets** in `gxa-<env>` for release history (`sh.helm.release.v1.gxa.*`). Without a Role, you get:

```text
secrets is forbidden: User "system:serviceaccount:gxa-jenkins:jenkins-cloud"
cannot list resource "secrets" in the namespace "gxa-<env>"
```

Copy the `jenkins-gxa-deploy` Role + RoleBinding for `gxa-staging` or `gxa-ci` in [`jenkins/fg-public-agent-rbac.yaml`](../jenkins/fg-public-agent-rbac.yaml). Set `metadata.namespace` and `atlas.ebi.ac.uk/target-namespace` to `gxa-<env>`. Apply **on the new cluster**:

```bash
kubectl --context <context> apply -f jenkins/<cluster>-agent-rbac.yaml
```

Verify:

```bash
kubectl --context <context> get role,rolebinding -n gxa-<env> \
  -l atlas.ebi.ac.uk/jenkins-role=deploy

kubectl --context <context> auth can-i list secrets \
  --namespace gxa-<env> \
  --as system:serviceaccount:gxa-jenkins:jenkins-cloud
```

Expect `yes`. Optional: the same Role in `gxa-<env>-solrcloud` if Jenkins will deploy SolrCloud.

## 7. Jenkins secrets credential

The pipeline mounts credential **`gxa-secrets-<env>`** as a Helm `-f` values file ([`Jenkinsfile`](../Jenkinsfile)).

**Manage Jenkins → Credentials → Secret file:**

| Field | Value |
| --- | --- |
| ID | `gxa-secrets-<env>` (e.g. `gxa-secrets-fallback`) |
| File | Same shape as gitignored `charts/gxa/.secrets-<env>.yaml` |

Typical keys: `jdbc.password`, `solr.password` (from the Solr bootstrap secret), `tomcat.deployerPassword` / `curatorPassword`, `imagePullSecret`, nginx cache purge password if used. Copy from an existing env’s local `.secrets-*.yaml`. Do not commit secrets.

Also add `gxa-<env>` in **Jenkins → DevOps Portal → Manage Environments** before the first non–dry-run deploy, and add `<env>` to the `Jenkinsfile` `ENV` choice list. Then run **Build Now** once so Jenkins refreshes parameters.
