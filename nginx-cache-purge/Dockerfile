# nginx:alpine with ngx_cache_purge as a dynamic module (OSS alternative to NGINX Plus proxy_cache_purge).
# https://github.com/nginx-modules/ngx_cache_purge
#
# Used by the GXA Helm sidecar. The chart ConfigMap must use proxy_cache_purge in a location
# (see README.md). The module is loaded via /etc/nginx/conf.d/00-cache-purge.conf in this image.

ARG NGINX_VERSION=1.29.5
ARG NGX_CACHE_PURGE_VERSION=2.5.6

FROM nginx:${NGINX_VERSION}-alpine AS builder

ARG NGINX_VERSION
ARG NGX_CACHE_PURGE_VERSION

RUN apk add --no-cache --virtual .build-deps \
        gcc \
        libc-dev \
        make \
        linux-headers \
        openssl-dev \
        pcre2-dev \
        zlib-dev \
        wget \
        tar \
    && wget -q "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O /tmp/nginx.tar.gz \
    && wget -q "https://github.com/nginx-modules/ngx_cache_purge/archive/refs/tags/${NGX_CACHE_PURGE_VERSION}.tar.gz" -O /tmp/purge.tar.gz \
    && mkdir -p /usr/src \
    && tar -xzf /tmp/nginx.tar.gz -C /usr/src \
    && tar -xzf /tmp/purge.tar.gz -C /usr/src \
    && PURGE_SRC="/usr/src/ngx_cache_purge-${NGX_CACHE_PURGE_VERSION}" \
    && cd "/usr/src/nginx-${NGINX_VERSION}" \
    # Re-use nginx image paths/modules, but drop --with-cc-opt/--with-ld-opt: unquoted expansion
    # turns compiler flags (e.g. -fstack-clash-protection) into invalid ./configure options.
    && NGINX_CONFIGURE="$(nginx -V 2>&1 | sed -n 's/^.*configure arguments: //p' \
        | sed -E "s/--with-cc-opt='[^']*'//g; s/--with-ld-opt='[^']*'//g")" \
    && eval "./configure --with-compat ${NGINX_CONFIGURE} --add-dynamic-module=${PURGE_SRC}" \
    && make -j"$(nproc)" modules \
    && apk del .build-deps \
    && rm -f /tmp/nginx.tar.gz /tmp/purge.tar.gz

ARG NGINX_VERSION=1.29.5
FROM nginx:${NGINX_VERSION}-alpine

COPY --from=builder /usr/src/nginx-*/objs/ngx_http_cache_purge_module.so /usr/lib/nginx/modules/

RUN echo 'load_module modules/ngx_http_cache_purge_module.so;' > /etc/nginx/conf.d/00-cache-purge.conf \
    && rm -f /etc/nginx/conf.d/default.conf
