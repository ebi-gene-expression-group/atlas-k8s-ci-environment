# New cluster setup (GXA)

Use this when GXA moves onto a **new Kubernetes cluster** (for example `hx-wp-webadmin-121` / `fg-fallback`), not when you only add another environment on **fg-public**. For a new env on an existing cluster, see [Adding a new deploy environment](../README.md#adding-a-new-deploy-environment).

Worked example throughout: `ENV=fallback`, context `fg-fallback`, app `gxa`. Substitute the new cluster’s context, NFS server, Postgres host, and Jenkins cloud name.

Recommended order:

1. Prerequisites (namespaces, kubeconfig, Jenkins cloud)
2. Solr CRDs and operator
3. Solr / ZK data directories on NFS
4. SolrCloud Helm chart
5. Database firewall
6. Webapp Helm chart
7. Jenkins deploy Role
8. Jenkins secrets credential

Solr data (step 3) must exist **before** the SolrCloud chart (step 4). Jenkins Role + secret (steps 7–8) can be done in parallel with 2–6, but Helm from Jenkins will fail until both exist.

## 1. Prerequisites

Ask ITS / CaaS for:

- A kubeconfig (or Jenkins Kubernetes cloud) that can schedule into this cluster
- Namespaces (team-admin typically **cannot** create them):
  - `gxa-jenkins` — Jenkins agent pods (`jenkins-k8s-pod-deploy.yaml`)
  - `gxa-<env>` — webapp (e.g. `gxa-fallback`)
  - `gxa-<env>-solrcloud` — SolrCloud (e.g. `gxa-fallback-solrcloud`)
- The cluster’s **writable** Isilon export and NFS server (Hinxton public uses `hh-isi-srv-vlan1496.ebi.ac.uk:/ifs/public`; HL2 fallback uses `hx-isi-srv-vlan157.ebi.ac.uk:/ifs/public-r`)
- Worker/pod CIDRs (needed for Postgres firewall and Isilon export ACLs)

Chart values live in `charts/gxa/values-<env>.yaml` and `charts/solr-cloud/values-<env>.yaml`. Scaffold the webapp values with `scripts/create-env.sh <env>` if they do not exist.

Set `.env` (or the shell) to the new cluster:

```bash
RELEASE=gxa
ENV=fallback
K8S_CONTEXT=fg-fallback
```

Confirm:

```bash
kubectl --context "$K8S_CONTEXT" get ns gxa-jenkins gxa-${ENV} gxa-${ENV}-solrcloud
```

### Jenkins Kubernetes cloud

The deploy pipeline (`Jenkinsfile`) picks the **Jenkins Kubernetes plugin cloud name** from `ENV`:

- `fallback` → `hx-webadmin-121`
- everything else → `hh-webadmin-35`

A new cluster needs a cloud of that name (or a `Jenkinsfile` change). The cloud must:

- Use a kubeconfig for **this** cluster
- Default / restrict agents to namespace `gxa-jenkins`
- Use service account `jenkins-cloud`

On the cluster, create `gxa-jenkins`, SA `jenkins-cloud`, and the `jenkins-agent-pods` Role/RoleBinding from [`jenkins/fg-public-agent-rbac.yaml`](../jenkins/fg-public-agent-rbac.yaml) (copy, retarget labels/context). Without that, Jenkins cannot even start the helm agent pod.

## 2. Solr CRDs and operator

Cluster-wide, once per cluster. Version used here: **Solr Operator 0.9.1** (includes the ZooKeeper operator). Official docs: [Running the Solr Operator](https://solr.apache.org/guide/operator/latest/getting-started/running-the-operator.html).

CRDs (Solr **and** `ZookeeperCluster` — Helm does not install dependency CRDs):

```bash
kubectl --context "$K8S_CONTEXT" create -f \
  https://solr.apache.org/operator/downloads/crds/v0.9.1/all-with-dependencies.yaml
```

Operator:

```bash
helm repo add apache-solr https://solr.apache.org/charts
helm repo update apache-solr
helm upgrade --install solr-operator apache-solr/solr-operator \
  --version 0.9.1 \
  --kube-context "$K8S_CONTEXT" \
  --namespace solr-operator \
  --create-namespace
```

`--create-namespace` may need cluster-admin. If it fails, ask ITS to create `solr-operator` first.

Verify:

```bash
kubectl --context "$K8S_CONTEXT" api-resources | grep -E 'solr|zookeeper'
kubectl --context "$K8S_CONTEXT" -n solr-operator get deploy,pods
```

### Team RBAC for SolrCloud CRs

CRDs being listed does **not** mean `team-admin` can create `SolrCloud` objects. Expect Helm error `cannot get resource "solrclouds"` otherwise.

```bash
kubectl --context "$K8S_CONTEXT" auth can-i '*' solrclouds --all-namespaces
```

Must print `yes`. `team-admin` cannot create ClusterRoles; **ITS** applies the ClusterRole + ClusterRoleBinding in [`charts/solr-cloud/README.md`](../charts/solr-cloud/README.md) (subject `default:team-admin`).

## 3. Solr / ZK data directories

Solr and ZooKeeper always use Isilon folders. There is no cluster PVC for Solr data. Detail: [`charts/solr-cloud/README.md`](../charts/solr-cloud/README.md) (NFS storage).

Layout:

```text
{nfs.publicPath}/{nfs.environmentsBase}/{environment}/{solr_data,zk_data}/
```

Example (HL2 fallback):

```text
hx-isi-srv-vlan157.ebi.ac.uk:/ifs/public-r/rw/fg/atlas/gxa/environments/fallback/solr_data/
hx-isi-srv-vlan157.ebi.ac.uk:/ifs/public-r/rw/fg/atlas/gxa/environments/fallback/zk_data/
```

Set `nfs.server` / `nfs.publicPath` in `charts/solr-cloud/values-<env>.yaml` (and the same server on the GXA chart).

### Populate the tree

Copy from an existing env (Codon datamover, as `fg_atlas`). See [`scripts/slurm/README.md`](../scripts/slurm/README.md).

If you rsync **staging → fallback**, ZK directory names and `zoo.cfg` FQDNs still say `gxa-staging-…`. Rewrite **before** deploy, with destination ZK stopped:

```bash
BASE=/nfs/ebi/public/rw/fg/atlas/gxa/environments SRC=staging DST=fallback \
  ./scripts/slurm/rewrite-gxa-zk-env-names.sh
```

Folder names the chart expects:

| Kind | Path under `solr_data` / `zk_data` |
| ---- | ---------------------------------- |
| Solr | `{dataDirPrefix}-solrcloud-{0..3}/` (often `gxa-solrcloud-n` when `dataDirPrefix: gxa`) |
| ZK   | `{release}-solrcloud-zookeeper-{0..2}/` (e.g. `gxa-fallback-solrcloud-zookeeper-n`) |

`dataDirPrefix` is in `values-<env>.yaml` when NFS names predate the Helm release rename.

### Write access from Kubernetes

Isilon must grant **read-write** on both `solr_data` and `zk_data` to **Kubernetes node IPs**, uid `fg_atlas` (2921) / gid 1146. `mount` can show `(rw)` while `touch` still returns `Read-only file system`.

NFS KB used for CaaS/Isilon: [KB0011170](https://embl.service-now.com/esc?id=kb_article&sysparm_article=KB0011170).

## 4. SolrCloud Helm chart

Namespace `gxa-<env>-solrcloud` must already exist.

```bash
K8S_CONTEXT=fg-fallback ENV=fallback FORCE_CONFLICTS=1 task deploy-solrcloud
```

Helm 4 on these clusters often needs `FORCE_CONFLICTS=1`. The task applies ZK NFS PV/PVCs **before** the operator creates StatefulSets (otherwise PVCs stay Pending).

Wait until 4 Solr + 3 ZK pods are Ready. Copy the Solr admin password the operator creates (needed by the webapp):

```bash
kubectl --context "$K8S_CONTEXT" -n gxa-${ENV}-solrcloud \
  get secret ${RELEASE}-${ENV}-solrcloud-security-bootstrap \
  -o jsonpath='{.data.admin}' | base64 -d; echo
```

Put that value in gitignored `charts/gxa/.secrets-<env>.yaml` under `solr.password`, and in the Jenkins credential (step 8). Default `changeme` will not talk to a real operator-managed Solr.

If ZK PVCs are Pending with no `volumeName`: `task fix-solrcloud-zk-pvcs ENV=<env>`. More in [`charts/solr-cloud/README.md`](../charts/solr-cloud/README.md).

## 5. Database firewall

The webapp uses an **external** Postgres (`jdbc.url` in `charts/gxa/values-<env>.yaml`), not in-cluster Postgres.

ITS must allow **TCP 5432** from this cluster’s worker (and if different, pod) networks to that host. Fallback example: `pgsql-dlvmpubfall2-019.ebi.ac.uk:5432` / database in `values-fallback.yaml`.

Check from a pod on the new cluster (Helm test or a throwaway probe):

```bash
# After the webapp chart exists, or with charts/gxa/templates/tests/test-jdbc.yaml:
helm test gxa -n gxa-${ENV} --filter name=gxa-test-jdbc
```

Or:

```bash
kubectl --context "$K8S_CONTEXT" -n gxa-${ENV} run pg-tcp --rm -it --restart=Never \
  --image=busybox:1.36 -- \
  nc -z -w 5 pgsql-dlvmpubfall2-019.ebi.ac.uk 5432
```

`FAIL: host:port is not reachable` is a firewall/network-policy problem, not a Helm values typo. Database name/user must also exist (`gxpatlaspub` vs `gxpatlaspro` has already bitten fallback).

## 6. Webapp Helm chart

Local (after `.secrets-<env>.yaml` has jdbc, solr, tomcat, image pull):

```bash
K8S_CONTEXT=fg-fallback ENV=fallback task deploy
```

Or Helm:

```bash
helm upgrade --install gxa charts/gxa \
  --kube-context "$K8S_CONTEXT" \
  --namespace gxa-${ENV} \
  --create-namespace \
  -f charts/gxa/values-${ENV}.yaml \
  -f charts/gxa/.secrets-${ENV}.yaml \
  --set appVersion=<tag> \
  --set image.tag=<tag>
```

`--create-namespace` may fail for `team-admin`; create `gxa-<env>` beforehand.

The first Ready wait includes `/gxa/json/experiments` (readiness probe, up to 10 minutes) so experiment cache is warm before the Service takes traffic. `kubectl rollout status` uses a 15 minute timeout.

Point `solr.namespace` at `gxa-<env>-solrcloud`. Chart details: [`charts/gxa/readme.md`](../charts/gxa/readme.md).

## 7. Jenkins deploy Role

The agent runs as `system:serviceaccount:gxa-jenkins:jenkins-cloud` **on this cluster**. Helm lists Secrets in `gxa-<env>` to find `sh.helm.release.v1.*`. Without a Role there you get:

```text
secrets is forbidden: User "system:serviceaccount:gxa-jenkins:jenkins-cloud"
cannot list resource "secrets" in API group "" in the namespace "gxa-<env>"
```

Copy the `jenkins-gxa-deploy` Role + RoleBinding for `gxa-staging` or `gxa-ci` from [`jenkins/fg-public-agent-rbac.yaml`](../jenkins/fg-public-agent-rbac.yaml). Change:

- `metadata.namespace`
- label `atlas.ebi.ac.uk/target-namespace`
- apply **on the new cluster** (`--context fg-fallback`, not `fg-public`)

The binding subject stays:

```yaml
subjects:
  - kind: ServiceAccount
    name: jenkins-cloud
    namespace: gxa-jenkins
```

Apply and check:

```bash
kubectl --context "$K8S_CONTEXT" apply -f jenkins/<this-cluster>-agent-rbac.yaml

kubectl --context "$K8S_CONTEXT" get role,rolebinding -n gxa-${ENV} \
  -l atlas.ebi.ac.uk/jenkins-role=deploy

kubectl --context "$K8S_CONTEXT" auth can-i list secrets \
  --namespace gxa-${ENV} \
  --as system:serviceaccount:gxa-jenkins:jenkins-cloud
```

The last command must print `yes`. Repeat the same Role/RoleBinding in `gxa-<env>-solrcloud` if Jenkins will install SolrCloud.

Also add `ENV` to the `Jenkinsfile` choice list and map it to this cluster’s Kubernetes cloud name (see Prerequisites).

## 8. Jenkins secrets credential

Pipeline credential id: **`gxa-secrets-<env>`** (see `Jenkinsfile`).

**Manage Jenkins → Credentials → Secret file:**

| Field | Value |
| ----- | ----- |
| ID | `gxa-secrets-fallback` (or `gxa-secrets-<env>`) |
| File | Same YAML as `charts/gxa/.secrets-<env>.yaml` |

Typical keys (only what that env’s values file needs):

```yaml
jdbc:
  password: "..."
solr:
  password: "..."   # from solrcloud-security-bootstrap, not changeme
tomcat:
  deployerPassword: "..."
  curatorPassword: "..."
imagePullSecret:
  create: yes
  username: "..."
  password: "..."
```

Do not commit `.secrets-*.yaml`. Copy from an existing env’s local file as a template.

Optional: add DevOps Portal environment label `gxa-<env>` before the first non–dry-run so `reportDeployOperation` succeeds ([README](../README.md#1-devops-portal-environment)).
