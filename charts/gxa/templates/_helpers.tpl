{{/*
Expand the name of the chart.
*/}}
{{- define "gxa.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "gxa.fullname" -}}
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
{{- define "gxa.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "gxa.labels" -}}
helm.sh/chart: {{ include "gxa.chart" . }}
{{ include "gxa.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "gxa.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gxa.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "gxa.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "gxa.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "gxa.jvmProxyArgs" -}}
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