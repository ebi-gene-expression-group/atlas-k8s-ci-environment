# GXA Helm Chart

This chart deploys the Gene Expression Atlas (GXA) web application on Kubernetes.
It provisions a Tomcat-based webapp Pod, mounts shared data from NFS and PVCs,
and wires in proxy settings and Solr credentials for upstream dependencies.

## High-level diagram

```mermaid
flowchart LR
  subgraph Release
    SVC[Service] --> POD[Deployment: gxa-webapp Pod]
    POD --> CM[ConfigMap: app config + Tomcat server.xml + logback]
    POD --> SEC[Secret: Tomcat users + JDBC + Solr creds]
    POD --> PROXY[ConfigMap: ebi-proxy]
    POD --> NFS[NFS volumes: gxa_codon, gxa, services, expdesign]
    POD --> PVC1[PVC: expdesign-rwo]
    POD --> PVC2[PVC: bulk-analytics-jsonl-rwm]
  end
  POD --> SOLR[External SolrCloud]
```

## What the chart includes

- **Deployment:** single Tomcat container (default image `tomcat:8-jdk11`) with optional JPDA debug port. See [templates/deployment.yaml](templates/deployment.yaml).
- **Service:** NodePort by default, exposing HTTP (and debug when enabled). See [templates/service.yaml](templates/service.yaml).
- **ConfigMaps:**
  - `{{ release }}-config` for `configuration.properties`, `server.xml`, `logback.xml`, and Solr settings. See [templates/configmap.yaml](templates/configmap.yaml).
  - `ebi-proxy` for HTTP/HTTPS proxy environment variables. See [templates/ebi-proxy.yaml](templates/ebi-proxy.yaml).
- **Secrets:**
  - `{{ release }}-secrets` for Tomcat users, JDBC config, and Solr credentials. See [templates/secret.yaml](templates/secret.yaml).
- **PVCs:** `expdesign-rwo` and `bulk-analytics-jsonl-rwm` (both kept by Helm). See [templates/expdesign-pvc.yaml](templates/expdesign-pvc.yaml) and [templates/bulk-analytics-pvc.yaml](templates/bulk-analytics-pvc.yaml).
- **Init containers:**
  - Snapshot experiments into an `emptyDir` via symlinks. See [templates/deployment.yaml](templates/deployment.yaml).
  - Seed the Tomcat manager app into an `emptyDir`. See [templates/deployment.yaml](templates/deployment.yaml).

## Volumes and mounts

- **NFS mounts (read-only where applicable):** `gxa_codon`, `gxa`, `services`, `expdesign`.
- **PVC mounts:** experiment design and bulk analytics JSONL data.
- **`emptyDir` mounts:** Tomcat logs, work, webapps, and `experiments-snapshot`.
- **Config/secret mounts:** webapp properties, Tomcat `server.xml`, and `tomcat-users.xml`.

## Proxy configuration

Proxy variables come from the `ebi-proxy` ConfigMap and are injected into the pod
as `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, and related variants. `CATALINA_OPTS`
is also populated to ensure Java-based proxy support.

## Images and repositories

- **Webapp:** `image.repository` + `image.tag` (defaults to `tomcat:8-jdk11`).
- **Init container:** `busybox` for the experiments snapshot setup.
- **Tomcat manager init:** uses the same `image.*` as the webapp.

## External dependencies

- **SolrCloud:** host and ZK endpoints are configured via `values.yaml` and injected
  into `configuration.properties` and secrets for authenticated access.
- **PostgreSQL:** by default the app connects to an **external** PG via `jdbc.url`.
  Optionally, the chart can provision an **in-cluster** PG (see below).

## Bundled PostgreSQL (optional)

By default `postgresql.enabled: false`, so environments connect to an external
PostgreSQL via `jdbc.url`. Set `postgresql.enabled: true` to have the chart
provision an in-cluster **PostgreSQL 16** `StatefulSet` + `Service` instead.

When enabled the chart creates two roles (passwords from the gitignored
`.secrets-<env>.yaml`):

- `atlasprd3` — read-only; this is the role the webapp connects as.
- `atlasdataload` — read/write; owns the `public` schema (used for data loading).

`atlasprd3` is granted `SELECT` on existing and future objects (via
`ALTER DEFAULT PRIVILEGES`), which keeps it effectively read-only. Role creation
and grants run once on first init via a `ConfigMap` mounted into
`/docker-entrypoint-initdb.d`; passwords are read from env vars with psql
`\getenv` so plaintext never lands in a ConfigMap.

When `postgresql.enabled` is true and `jdbc.url` is left unset, `jdbc.url`
auto-derives to the in-cluster Service
(`jdbc:postgresql://{release}-postgresql.{namespace}.svc.cluster.local:5432/{database}`).
`jdbc.password` must equal `postgresql.atlasprd3Password` (the webapp connects as
atlasprd3).

Data is stored on a `volumeClaimTemplate` using the cluster default StorageClass
(set `postgresql.persistence.storageClassName` to override, or
`postgresql.persistence.enabled: false` for an ephemeral `emptyDir`).

### Data population job (pg_dump -> psql)

Set `postgresql.populate.enabled: true` to run a **plain background Job** that
streams `pg_dump` from a source DB straight into `psql` on the in-cluster DB as
`atlasdataload` (no intermediate file, so no scratch volume needed). It is a
normal Job (not a Helm hook), so helm does not block on it — useful for large
datasets that take far longer than helm's hook timeout. Configure the source
under `postgresql.populate.source.*` (password via `.secrets-<env>.yaml`).
Default `dumpArgs` (`--no-owner --no-privileges --clean --if-exists`) make the
restore portable and re-runs idempotent.

The Job runs once and is retained on completion (so later `helm upgrade`s are
no-ops). To re-populate, delete it and re-deploy:
`kubectl delete job {release}-pg-populate`.

Size `postgresql.persistence.size` with headroom for the restored data (indexes,
WAL) — e.g. the `ci` environment uses `50Gi` for a ~17 GB source DB.

## Namespaces and environments

- The chart does not create a `Namespace` resource. Use Helm's `--create-namespace`
  (already used by `make deploy`) or create the namespace ahead of time.
- Each environment is expected to have its own values file named
  `values-<env>.yaml` under `charts/gxa/`.
- The `ci` environment (`values-ci.yaml`) provisions an in-cluster PostgreSQL and
  populates it from the staging source DB; it expects a `gxa-ci-solrcloud`
  SolrCloud namespace to exist.
- You can scaffold a new environment values file from the test template:
  `scripts/create-env.sh <env> [release]` (defaults to `gxa`).

## Configuration

### Webapp configuration

Key | Default | Description
--- | --- | ---
`image.repository` | `tomcat` | Webapp container image repository.
`image.tag` | `8-jdk11` | Webapp container image tag (defaults to chart appVersion when empty).
`nameOverride` | `""` | Overrides the chart name for resource naming.
`fullnameOverride` | `""` | Overrides the full resource name.
`serviceAccount.create` | `false` | Create a dedicated ServiceAccount.
`serviceAccount.annotations` | `{}` | Annotations for the ServiceAccount.
`serviceAccount.name` | `""` | ServiceAccount name override.
`podAnnotations` | `{}` | Extra annotations applied to the pod.
`podSecurityContext.runAsUser` | `2921` | Pod user ID for filesystem ownership.
`podSecurityContext.runAsGroup` | `1146` | Pod group ID for filesystem ownership.
`resources` | `{}` | Pod resource requests/limits.
`tomcat.httpPort` | `8080` | Tomcat HTTP port inside the container.
`tomcat.deployerPassword` | unset | Tomcat deployer password.
`tomcat.curatorPassword` | unset | Tomcat curator password.
`loggingLevel` | `DEBUG` | Application logging level.
`jdbc.populator.run` | unset | Enable JDBC populator job if defined.
`jdbc.url` | unset | JDBC URL for the GXA database (auto-derived to the in-cluster Service when `postgresql.enabled` and unset).
`jdbc.password` | unset | JDBC password for the GXA database (must equal `postgresql.atlasprd3Password` when using the bundled PG).
`postgresql.enabled` | `false` | Provision an in-cluster PostgreSQL 16 instead of using an external DB.
`postgresql.database` | `gxpatlas` | In-cluster database name.
`postgresql.superuser` | `postgres` | In-cluster superuser role.
`postgresql.superuserPassword` | `""` | Superuser password (set via `.secrets-<env>.yaml`).
`postgresql.atlasprd3Password` | `""` | Read-only role password (set via `.secrets-<env>.yaml`).
`postgresql.atlasdataloadPassword` | `""` | Read/write role password (set via `.secrets-<env>.yaml`).
`postgresql.persistence.enabled` | `true` | Use a PVC for DB data (else ephemeral `emptyDir`).
`postgresql.persistence.size` | `20Gi` | PVC size for DB data.
`postgresql.persistence.storageClassName` | `""` | StorageClass for the PVC (empty -> cluster default).
`postgresql.populate.enabled` | `false` | Run the streaming pg_dump -> psql population Job (plain background Job).
`postgresql.populate.source.host` | `""` | Source DB host for `pg_dump`.
`postgresql.populate.source.database` | `""` | Source DB name for `pg_dump`.
`postgresql.populate.source.user` | `atlasprd3` | Source DB user for `pg_dump`.
`postgresql.populate.source.password` | `""` | Source DB password (set via `.secrets-<env>.yaml`).
`postgresql.populate.dumpArgs` | `--no-owner --no-privileges --clean --if-exists` | Flags passed to `pg_dump`.
`solr.namespace` | unset | Namespace where SolrCloud is deployed.
`solr.user` | unset | Solr username.
`solr.password` | unset | Solr password.
`solr.collection` | unset | Default Solr collection name.
`solr.timeout` | unset | Solr client timeout (ms).
`nfs.server` | `hh-isi-srv-vlan1496.ebi.ac.uk` | NFS server hostname.

### Network access

Key | Default | Description
--- | --- | ---
`service.type` | `NodePort` | Service type for the webapp.
`service.port` | `80` | Service port for HTTP.
`ingress.enabled` | `true` | Create an Ingress resource.
`ingress.pathPrefix` | `/gxa` | Path prefix for regex routing and health bypass.
`ingress.cache.enabled` | `false` | Enable ingress-nginx `proxy-cache` annotations on the Ingress.
`ingress.cache.zoneName` | `gxa_cache` | `keys_zone` name (must match controller `http-snippet`).
`ingress.cache.valid200` | `60d` | TTL for cached 200 responses.
`ingress.cache.controllerCachePath` | `/tmp/gxa-nginx-cache` | Disk path in controller `proxy_cache_path` snippet.

**Ingress proxy cache** stores responses on the ingress-nginx controller, not in the GXA pod. Before enabling `ingress.cache.enabled`, merge `docs/ingress-nginx-values-gxa-cache.yaml` into the **ingress-nginx** Helm release (`ingress` namespace) — do not patch the ConfigMap by hand, or the next controller upgrade will revert it. Prefer `nginx.cache.enabled: false` when using ingress cache. Purge by clearing files under `controllerCachePath` on controller pods or restarting them.

### Debugging

Key | Default | Description
--- | --- | ---
`tomcat.debug.enabled` | `false` | Enable JPDA debug port.
`tomcat.debug.port` | `8000` | JPDA debug port.
`tomcat.debug.address` | `*:8000` | JPDA bind address.
