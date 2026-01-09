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
-Dhttp.nonProxyHosts=$(echo ${NO_PROXY} | sed 's/,/|/g')
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

{{- define "app.bioentityPropertiesDir" -}}
{{ include "app.dataDir" . }}/bioentity_properties
{{- end }}

{{- define "app.bioentityPropertiesSourceDir" -}}
{{ include "app.dataDir" . }}/bioentity_properties_source
{{- end }}

{{- define "app.bulkAnalyticsJsonlDir" -}}
{{ include "app.dataDir" . }}/bulk-analytics-jsonl
{{- end }}

{{- define "app.bioentitiesJsonlDir" -}}
{{ include "app.dataDir" . }}/bioentities-jsonl
{{- end }}

{{/*
Source directory for experiments on NFS
*/}}
{{- define "app.experimentsSourceDir" -}}
{{- include "app.servicesDir" . -}}/fg/atlas/{{- .Values.nfs.snapshotComponent -}}
{{- end }}

{{/*
Gradle CLI arguments for running the CLI application
*/}}
{{- define "app.gradleCliArgs" -}} 
--quiet \
{{ include "app.jvmProxyArgs" . }} 
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


{{- define "app.gxaCodonVolume" -}}
- name: codon-volume
  nfs:
    server: {{ .Values.nfs.server }}
    path: /ifs/public/ro/gxa_codon
{{- end }}

{{- define "app.servicesVolume" -}}
- name: services-volume
  nfs:
    server: {{ .Values.nfs.server }}
    path: /ifs/public/services
{{- end }}

{{- define "app.expdesignVolume" -}}
- name: expdesign-volume
  nfs:
    server: {{ .Values.nfs.server }}
    path: /ifs/public/services/fg/atlas/experiments_test/expDesign
    readOnly: true
{{- end }}

{{- define "app.gxaVolume" -}}
- name: gxa-volume
  nfs:
    server: {{ .Values.nfs.server }}
    path: /ifs/public/ro/gxa
{{- end }}

{{- define "app.bulkAnalyticsJsonlVolume" -}}
- name: bulk-analytics-jsonl-vol
  persistentVolumeClaim:
    claimName: bulk-analytics-jsonl-rwm
{{- end }}

{{- define "app.bioentitiesJsonlVolume" -}}
- name: bioentities-jsonl-vol
  persistentVolumeClaim:
    claimName: bioentities-jsonl-rwo
{{- end }}
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
{{ .Values.solr.namespace }}-zookeeper-client.{{ .Values.solr.namespace }}.svc.cluster.local:2181
{{- end }}

{{/*
Solr hosts URL
*/}}
{{- define "app.solrHost" -}}
{{ .Values.solr.namespace }}-common.{{ .Values.solr.namespace }}.svc.cluster.local
{{- end }}