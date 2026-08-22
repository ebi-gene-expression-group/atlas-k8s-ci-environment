# nginx-cache-purge

Custom `nginx:alpine` image with the [ngx_cache_purge](https://github.com/nginx-modules/ngx_cache_purge) dynamic module for the GXA sidecar proxy cache.

Registry image: `dockerhub.ebi.ac.uk/ebi-gene-expression/atlas-web-bulk/nginx-cache-purge`

## Build and push

From the `atlas-k8s-ci-environment` repo root (requires Docker and registry credentials):

```bash
export REGISTRY_USER=...
export REGISTRY_PASSWORD=...   # EBI dockerhub API key

task nginx-cache-purge:build-push
# or: TAG=1.29.5 task nginx-cache-purge:build-push
```

## Helm (GXA chart)

The chart loads the module and exposes authenticated purge endpoints when `nginx.cache.purge.opsAuth.enabled` is true.

```yaml
nginx:
  cache:
    purge:
      opsAuth:
        username: cacheops          # values.yaml
        password: "..."               # .secrets-<env>.yaml
```

| Action | curl example |
|--------|----------------|
| One cached URL | `curl -u <username>:$PASS -X PURGE "https://host/gxa/_ops/cache/purge/gxa/json/experiments"` |
| Prefix (`*`) | `curl -u <username>:$PASS -X PURGE "https://host/gxa/_ops/cache/purge-prefix/gxa/json/experiments"` |
| Entire sidecar zone | `curl -u <username>:$PASS -X PURGE "https://host/gxa/_ops/cache/purge-all"` |

See `charts/gxa/readme.md` for full purge documentation.

## Verify module

```bash
docker run --rm dockerhub.ebi.ac.uk/ebi-gene-expression/atlas-web-bulk/nginx-cache-purge:1.29.5 nginx -V 2>&1
ls /usr/lib/nginx/modules/ngx_http_cache_purge_module.so
```
