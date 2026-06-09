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

Point the sidecar at this image:

```yaml
nginx:
  image:
    repository: dockerhub.ebi.ac.uk/ebi-gene-expression/atlas-web-bulk/nginx-cache-purge
    tag: "1.29.5"
```

The GXA chart loads the module (`load_module modules/ngx_http_cache_purge_module.so;` at the top of `nginx.conf`)
and enables purge on the cached `location /` block (`proxy_cache_key "$uri$is_args$args"`).
Allowed clients are set in `nginx.cache.purge.allow` (private RFC1918 ranges + localhost by default).

Purge one URL (from inside the pod):

```bash
curl -X PURGE "http://127.0.0.1:8081/gxa/json/experiments"
```

Purge entire zone (only if `nginx.cache.purge.allowPurgeAll: true` — any PURGE from an allowed client clears the zone):

```bash
curl -X PURGE "http://127.0.0.1:8081/gxa/json/health"
```

## Verify module

```bash
docker run --rm dockerhub.ebi.ac.uk/ebi-gene-expression/atlas-web-bulk/nginx-cache-purge:1.29.5 nginx -V 2>&1
ls /usr/lib/nginx/modules/ngx_http_cache_purge_module.so
```
