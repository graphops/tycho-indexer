{{/*
Expand the name of the chart.
*/}}
{{- define "tycho-indexer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "tycho-indexer.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tycho-indexer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "tycho-indexer.labels" -}}
helm.sh/chart: {{ include "tycho-indexer.chart" . }}
{{ include "tycho-indexer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "tycho-indexer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tycho-indexer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return pod annotations merged with chart-level annotations.
*/}}
{{- define "tycho-indexer.podAnnotations" -}}
{{- $annotations := dict -}}
{{- if .Values.annotations -}}
{{- $annotations = merge $annotations .Values.annotations -}}
{{- end -}}
{{- if .Values.podAnnotations -}}
{{- $annotations = merge $annotations .Values.podAnnotations -}}
{{- end -}}
{{- if gt (len $annotations) 0 -}}
{{- toYaml $annotations -}}
{{- end -}}
{{- end }}

{{/*
Return pod labels merged with selector labels.
*/}}
{{- define "tycho-indexer.podLabels" -}}
{{- $labels := fromYaml (include "tycho-indexer.selectorLabels" .) -}}
{{- if .Values.podLabels -}}
{{- $labels = merge $labels .Values.podLabels -}}
{{- end -}}
{{- toYaml $labels -}}
{{- end }}

{{/*
Helper to render annotations map.
*/}}
{{- define "tycho-indexer.renderAnnotations" -}}
{{- if . -}}
{{- toYaml . -}}
{{- end -}}
{{- end }}

{{/*
Render environment variables from a key/value map.
*/}}
{{- define "tycho-indexer.envVarsFromMap" -}}
{{- $map := . -}}
{{- $keys := keys $map | sortAlpha -}}
{{- range $keys }}
- name: {{ . }}
  value: {{ index $map . | quote }}
{{- end }}
{{- end }}

{{/*
Build the env var list configured via .Values.env.
*/}}
{{- define "tycho-indexer.buildEnvVars" -}}
{{- $root := .root -}}
{{- $env := .env -}}
{{- $target := .target -}}
{{- $envList := list -}}
{{- if $env.static }}
  {{- $keys := keys $env.static | sortAlpha -}}
  {{- range $keys }}
    {{- $value := tpl (printf "%v" (index $env.static .)) $root -}}
    {{- $envList = append $envList (dict "name" . "value" $value) -}}
  {{- end }}
{{- end }}
{{- range $env.secretRefs }}
  {{- $secret := . -}}
  {{- $keys := keys $secret.keys | sortAlpha -}}
  {{- range $keys }}
    {{- $ref := dict "name" $secret.name "key" (index $secret.keys .) -}}
    {{- if hasKey $secret "optional" }}
      {{- $_ := set $ref "optional" $secret.optional -}}
    {{- end }}
    {{- $envList = append $envList (dict "name" . "valueFrom" (dict "secretKeyRef" $ref)) -}}
  {{- end }}
{{- end }}
{{- range $env.configMapRefs }}
  {{- $config := . -}}
  {{- $keys := keys $config.keys | sortAlpha -}}
  {{- range $keys }}
    {{- $ref := dict "name" $config.name "key" (index $config.keys .) -}}
    {{- if hasKey $config "optional" }}
      {{- $_ := set $ref "optional" $config.optional -}}
    {{- end }}
    {{- $envList = append $envList (dict "name" . "valueFrom" (dict "configMapKeyRef" $ref)) -}}
  {{- end }}
{{- end }}
{{- range $env.fieldRefs }}
  {{- $field := dict "fieldRef" (dict "fieldPath" .fieldPath) -}}
  {{- if .apiVersion }}
    {{- $_ := set (index $field "fieldRef") "apiVersion" .apiVersion -}}
  {{- end }}
  {{- $envList = append $envList (dict "name" .name "valueFrom" $field) -}}
{{- end }}
{{- range $env.resourceFieldRefs }}
  {{- $ref := dict "resource" .resource -}}
  {{- if .containerName }}
    {{- $_ := set $ref "containerName" .containerName -}}
  {{- end }}
  {{- if .divisor }}
    {{- $_ := set $ref "divisor" .divisor -}}
  {{- end }}
  {{- $envList = append $envList (dict "name" .name "valueFrom" (dict "resourceFieldRef" $ref)) -}}
{{- end }}
{{- range $env.extra }}
  {{- $envList = append $envList . -}}
{{- end }}
{{- $_ := set $target "list" $envList -}}
{{- end }}

{{/*
Build the envFrom list configured via .Values.envFrom.
*/}}
{{- define "tycho-indexer.buildEnvFrom" -}}
{{- $envFrom := .envFrom -}}
{{- $target := .target -}}
{{- $list := list -}}
{{- range $envFrom.secrets }}
  {{- if kindIs "map" . -}}
    {{- $source := dict "name" .name -}}
    {{- if hasKey . "optional" }}
      {{- $_ := set $source "optional" .optional -}}
    {{- end }}
    {{- $list = append $list (dict "secretRef" $source) -}}
  {{- else -}}
    {{- $list = append $list (dict "secretRef" (dict "name" .)) -}}
  {{- end }}
{{- end }}
{{- range $envFrom.configMaps }}
  {{- if kindIs "map" . -}}
    {{- $source := dict "name" .name -}}
    {{- if hasKey . "optional" }}
      {{- $_ := set $source "optional" .optional -}}
    {{- end }}
    {{- $list = append $list (dict "configMapRef" $source) -}}
  {{- else -}}
    {{- $list = append $list (dict "configMapRef" (dict "name" .)) -}}
  {{- end }}
{{- end }}
{{- range $envFrom.extra }}
  {{- $list = append $list . -}}
{{- end }}
{{- $_ := set $target "list" $list -}}
{{- end }}

{{/* Append a single env var entry to the provided accumulator. */}}
{{- define "tycho-indexer.appendEnvVar" -}}
{{- $target := .target -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- $source := .source -}}
{{- if $source }}
  {{- $entry := dict "name" $name -}}
  {{- if kindIs "string" $source }}
    {{- $_ := set $entry "value" (tpl (printf "%v" $source) $root) -}}
  {{- else if kindIs "map" $source }}
    {{- if hasKey $source "value" }}
      {{- $_ := set $entry "value" (tpl (printf "%v" ($source.value | default "")) $root) -}}
    {{- end }}
    {{- if hasKey $source "secretKeyRef" }}
      {{- $_ := set $entry "valueFrom" (dict "secretKeyRef" $source.secretKeyRef) -}}
    {{- else if hasKey $source "configMapKeyRef" }}
      {{- $_ := set $entry "valueFrom" (dict "configMapKeyRef" $source.configMapKeyRef) -}}
    {{- end }}
  {{- end }}
  {{- $_ := set $target "list" (append (index $target "list") $entry) -}}
{{- end }}
{{- end }}

{{/*
Resolve the service account name to use.
*/}}
{{- define "tycho-indexer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- include "tycho-indexer.fullname" . -}}
{{- end -}}
{{- else -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- "default" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Compute the Argo CD sync wave for a resource.
*/}}
{{- define "tycho-indexer.syncWave" -}}
{{- $base := 0 -}}
{{- if hasKey . "base" -}}
{{- $base = .base -}}
{{- end -}}
{{- $offset := 0 -}}
{{- if hasKey . "offset" -}}
{{- $offset = .offset -}}
{{- end -}}
{{- printf "%d" (add $base $offset) -}}
{{- end }}
