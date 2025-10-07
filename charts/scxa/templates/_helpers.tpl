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