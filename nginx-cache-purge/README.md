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

Add a purge location to the chart `nginx.conf` (example — restrict to internal callers):

```nginx
location ~ ^/gxa/purge(/.*)$ {
    allow 127.0.0.1;
    deny all;
    proxy_cache_purge gxa_cache "$1$is_args$args";
}
```

Purge request (from inside the pod):

```bash
curl -X PURGE "http://127.0.0.1:8081/gxa/purge/json/experiments"
```

Adjust the regex and `proxy_cache_key` so the purge key matches cached entries.

## Verify module

```bash
docker run --rm dockerhub.ebi.ac.uk/ebi-gene-expression/atlas-web-bulk/nginx-cache-purge:1.29.5 nginx -V 2>&1
ls /usr/lib/nginx/modules/ngx_http_cache_purge_module.so
```
