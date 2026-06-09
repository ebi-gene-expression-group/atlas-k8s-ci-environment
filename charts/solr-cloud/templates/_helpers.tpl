{{/*
Expand the name of the chart.
*/}}
{{- define "solr-cloud.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "solr-cloud.fullname" -}}
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
{{- define "solr-cloud.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "solr-cloud.labels" -}}
helm.sh/chart: {{ include "solr-cloud.chart" . }}
{{ include "solr-cloud.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "solr-cloud.selectorLabels" -}}
app.kubernetes.io/name: {{ include "solr-cloud.name" . }}
app.kubernetes.io/component: solr-cloud
app.kubernetes.io/part-of: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "solr-cloud.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "solr-cloud.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Solr operator StatefulSet volumeClaimTemplate name is "data"; PVCs are
data-<release>-solrcloud-<ordinal> (e.g. data-gxa-dev-solrcloud-0).
Pod names use the Helm release name; NFS data folders may use dataDirPrefix.
*/}}
{{- define "solr-cloud.solrPodName" -}}
{{- printf "%s-solrcloud-%d" .releaseName .ordinal }}
{{- end }}

{{- define "solr-cloud.solrDataDirName" -}}
{{- printf "%s-solrcloud-%d" .dataDirPrefix .ordinal }}
{{- end }}

{{- define "solr-cloud.solrDataPvcName" -}}
{{- printf "data-%s-solrcloud-%d" .releaseName .ordinal }}
{{- end }}

{{- define "solr-cloud.solrDataPvName" -}}
{{- printf "%s-solr-data-%d" .releaseName .ordinal }}
{{- end }}

{{/*
Provided ZK StatefulSet volumeClaimTemplate name is "data"; PVCs are
data-<release>-solrcloud-zookeeper-<ordinal>.
*/}}
{{- define "solr-cloud.zkDataDirName" -}}
{{- printf "%s-solrcloud-zookeeper-%d" .dataDirPrefix .ordinal }}
{{- end }}

{{- define "solr-cloud.zkDataPvcName" -}}
{{- printf "data-%s-solrcloud-zookeeper-%d" .releaseName .ordinal }}
{{- end }}

{{- define "solr-cloud.zkDataPvName" -}}
{{- printf "%s-zk-data-%d" .releaseName .ordinal }}
{{- end }}

{{- define "solr-cloud.solrNfsDataBasePath" -}}
{{- $nfsData := .Values.solr.storage.nfsData | default dict -}}
{{- if $nfsData.basePath -}}
{{- $nfsData.basePath -}}
{{- else -}}
{{- $base := required "nfs.environmentsBase is required when solr.storage.nfsData is enabled without basePath" .Values.nfs.environmentsBase -}}
{{- $env := required "environment is required when solr.storage.nfsData is enabled without basePath" .Values.environment -}}
{{- printf "%s/%s/solr_data" $base $env -}}
{{- end -}}
{{- end }}

{{- define "solr-cloud.solrNfsDataMode" -}}
{{- default "pod" (.Values.solr.storage.nfsData.mode) -}}
{{- end }}

{{- define "solr-cloud.zkNfsDataMode" -}}
{{- default "pod" (.Values.zookeeper.storage.nfsData.mode) -}}
{{- end }}

{{- define "solr-cloud.solrNfsDataPodMode" -}}
{{- $nfsData := .Values.solr.storage.nfsData | default dict -}}
{{- if and ($nfsData.enabled | default false) (eq (default "pod" $nfsData.mode) "pod") -}}true{{- end -}}
{{- end }}

{{- define "solr-cloud.zkNfsDataPodMode" -}}
{{- $nfsData := .Values.zookeeper.storage.nfsData | default dict -}}
{{- if and ($nfsData.enabled | default false) (eq (default "pod" $nfsData.mode) "pod") -}}true{{- end -}}
{{- end }}

{{- define "solr-cloud.zkNfsDataBasePath" -}}
{{- $nfsData := .Values.zookeeper.storage.nfsData | default dict -}}
{{- if $nfsData.basePath -}}
{{- $nfsData.basePath -}}
{{- else -}}
{{- $base := required "nfs.environmentsBase is required when zookeeper.storage.nfsData is enabled without basePath" .Values.nfs.environmentsBase -}}
{{- $env := required "environment is required when zookeeper.storage.nfsData is enabled without basePath" .Values.environment -}}
{{- printf "%s/%s/zk_data" $base $env -}}
{{- end -}}
{{- end }}