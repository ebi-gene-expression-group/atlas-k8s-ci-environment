{{/*
Expand the name of the chart.
*/}}
{{- define "app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "app.labels" -}}
helm.sh/chart: {{ include "app.chart" . }}
{{ include "app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Extra nginx configuration-snippet for ingress cache (health bypass, cache methods, debug header).
Used with nginx.ingress.kubernetes.io/proxy-cache annotation referencing keys_zone from controller http-snippet.
*/}}
{{- define "app.ingress.cacheConfigurationSnippet" -}}
proxy_cache_methods GET HEAD;
set $skip_cache 0;
if ($request_uri = {{ .Values.ingress.pathPrefix }}/json/health) {
  set $skip_cache 1;
}
proxy_cache_bypass $skip_cache;
proxy_no_cache $skip_cache;
add_header X-Cache-Status $upstream_cache_status;
{{- end }}

{{/*
Ingress host: optional override, or {environment}.{hostBase} when both are set.
hostBase is cluster-specific and supplied at deploy time (not the full URL in the chart).
*/}}
{{- define "app.ingress.host" -}}
{{- if .Values.ingress.host -}}
{{- .Values.ingress.host -}}
{{- else if and .Values.environment .Values.ingress.hostBase -}}
{{- printf "%s.%s" .Values.environment .Values.ingress.hostBase -}}
{{- end -}}
{{- end }}

{{/*
Ingress annotations: user values plus optional ingress-nginx proxy cache.
*/}}
{{- define "app.ingress.annotations" -}}
{{- $ann := deepCopy (.Values.ingress.annotations | default dict) }}
{{- if .Values.ingress.cache.enabled }}
{{- $_ := set $ann "nginx.ingress.kubernetes.io/proxy-buffering" "on" }}
{{- $_ := set $ann "nginx.ingress.kubernetes.io/proxy-read-timeout" (.Values.ingress.cache.proxyReadTimeout | default "600") }}
{{- $_ := set $ann "nginx.ingress.kubernetes.io/proxy-send-timeout" (.Values.ingress.cache.proxySendTimeout | default "600") }}
{{- $_ := set $ann "nginx.ingress.kubernetes.io/proxy-cache" .Values.ingress.cache.zoneName }}
{{- $_ := set $ann "nginx.ingress.kubernetes.io/proxy-cache-valid" (printf "200 %s" .Values.ingress.cache.valid200) }}
{{- $_ := set $ann "nginx.ingress.kubernetes.io/configuration-snippet" (include "app.ingress.cacheConfigurationSnippet" .) }}
{{- end }}
{{- toYaml $ann }}
{{- end }}

{{/*
http-snippet to merge into the ingress-nginx controller ConfigMap (not applied by this chart).
*/}}
{{- define "app.ingress.controllerHttpSnippet" -}}
proxy_cache_path {{ .Values.ingress.cache.controllerCachePath }} levels=1:2 keys_zone={{ .Values.ingress.cache.zoneName }}:{{ .Values.ingress.cache.zoneSize }} max_size={{ .Values.ingress.cache.maxSize }} inactive={{ .Values.ingress.cache.inactive }} use_temp_path=off;
{{- end }}

{{/* Minimal RBAC rules for jobs read access when using kubectl in init containers */}}
{{- define "app.jobsRbac" -}}
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "app.fullname" . }}-jobs-reader
  labels:
    {{- include "app.labels" . | nindent 4 }}
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "app.fullname" . }}-jobs-reader-binding
  labels:
    {{- include "app.labels" . | nindent 4 }}
subjects:
- kind: ServiceAccount
  name: {{ include "app.serviceAccountName" . }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ include "app.fullname" . }}-jobs-reader
{{- end }}

{{- define "app.jvmProxyArgs" -}}

{{- /* Convert comma-separated NO_PROXY to Java's pipe-separated format 
When used in a container, needs env variables to be set up, e.g. from a configmap.
Notes:
1. the last system property arg is not followed by a backslash
2. fpr the non proxy hosts, we use substitution
*/ -}}
-Dhttp.proxyHost=${PROXY_HOST} \
-Dhttp.proxyPort=${PROXY_PORT} \
-Dhttps.proxyHost=${PROXY_HOST} \
-Dhttps.proxyPort=${PROXY_PORT} \
-Dhttp.nonProxyHosts=${NO_PROXY//,/|}
{{- end }}

{{- define "app.jvmProxyArgsSingleLine" -}}
{{- /* Single-line version for environment variables (CATALINA_OPTS, JAVA_OPTS, etc.) */ -}}
-Dhttp.proxyHost=${PROXY_HOST} -Dhttp.proxyPort=${PROXY_PORT} -Dhttps.proxyHost=${PROXY_HOST} -Dhttps.proxyPort=${PROXY_PORT} -Dhttp.nonProxyHosts=${NO_PROXY//,/|}
{{- end }}

{{/*
Root directory for data mounts
*/}}
{{- define "app.dataDir" -}}
/atlas-data
{{- end }}

{{- define "app.experimentsDir" -}}
{{ include "app.dataDir" . }}/exp
{{- end }}

{{- define "app.expdesignDir" -}}
{{ include "app.dataDir" . }}/expdesign
{{- end }}

{{- define "app.servicesDir" -}}
{{ include "app.dataDir" . }}/services
{{- end }}

{{- define "app.tomcatDir" -}}
/usr/local/tomcat
{{- end }}

{{/*
Source directory for experiments on NFS
*/}}
{{- define "app.experimentsSourceDir" -}}
{{ include "app.dataDir" . }}/gxa_codon/.snapshot/gxa_codon_2025-10-14_13:34/experiments
{{- end }}


{{/*
Proxy environment variables, used in containers
*/}}
{{- define "app.proxyEnv" -}}
- name: HTTP_PROXY
  valueFrom:
    configMapKeyRef:
      name: ebi-proxy
      key: HTTP_PROXY
- name: HTTPS_PROXY
  valueFrom:
    configMapKeyRef:
      name: ebi-proxy
      key: HTTPS_PROXY
- name: http_proxy
  valueFrom:
    configMapKeyRef:
      name: ebi-proxy
      key: HTTP_PROXY
- name: https_proxy
  valueFrom:
    configMapKeyRef:
      name: ebi-proxy
      key: HTTPS_PROXY
- name: NO_PROXY
  valueFrom:
    configMapKeyRef:
      name: ebi-proxy
      key: NO_PROXY
- name: PROXY_HOST
  valueFrom:
    configMapKeyRef:
      name: ebi-proxy
      key: PROXY_HOST
- name: PROXY_PORT
  valueFrom:
    configMapKeyRef:
      name: ebi-proxy
      key: PROXY_PORT
{{- end }}

{{/*
NFS volume mounts, used in deployments and jobs
*/}}

{{/*
Secrets volume mount
*/}}
{{- define "app.secretsVolume" -}}
- name: {{ include "app.name" . }}-secrets
  secret:
    secretName: {{ include "app.fullname" . }}-secrets
{{- end }}

{{/*
Solr Zookeeper hosts URL
*/}}
{{- define "app.solrZkHosts" -}}
{{ include "app.name" . }}-solrcloud-zookeeper-client.{{ .Values.solr.namespace }}.svc.cluster.local:2181
{{- end }}

{{/*
Solr hosts URL
*/}}
{{- define "app.solrHost" -}}
{{ include "app.name" . }}-solrcloud-common.{{ .Values.solr.namespace }}.svc.cluster.local
{{- end }}

{{/*
In-cluster PostgreSQL Service hostname (FQDN within the release namespace)
*/}}
{{- define "app.postgresqlHost" -}}
{{ include "app.fullname" . }}-postgresql.{{ .Release.Namespace }}.svc.cluster.local
{{- end }}

{{/*
JDBC URL: explicit jdbc.url wins; otherwise derive from the in-cluster
PostgreSQL Service when postgresql.enabled.
*/}}
{{- define "app.jdbcUrl" -}}
{{- if .Values.jdbc.url -}}
{{- .Values.jdbc.url -}}
{{- else if and .Values.postgresql .Values.postgresql.enabled -}}
{{- printf "jdbc:postgresql://%s:%v/%s" (include "app.postgresqlHost" .) .Values.postgresql.service.port .Values.postgresql.database -}}
{{- end -}}
{{- end }}

{{/* Name of the chart-managed registry pull secret */}}
{{- define "app.registryPullSecretName" -}}
{{- if .Values.imagePullSecret.name }}
{{- .Values.imagePullSecret.name | trunc 253 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-registry" (include "app.fullname" .) | trunc 253 | trimSuffix "-" }}
{{- end }}
{{- end }}