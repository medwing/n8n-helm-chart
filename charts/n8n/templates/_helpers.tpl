{{/*
Expand the name of the chart.
*/}}
{{- define "n8n.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "n8n.fullname" -}}
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
{{- define "n8n.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "n8n.labels" -}}
helm.sh/chart: {{ include "n8n.chart" . }}
{{ include "n8n.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "n8n.selectorLabels" -}}
app.kubernetes.io/name: {{ include "n8n.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/* Create the name of the service account to use */}}
{{- define "n8n.serviceAccountName" -}}
{{- if .Values.main.serviceAccount.create }}
{{- default (include "n8n.fullname" .) .Values.main.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.main.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* PVC existing, emptyDir, Dynamic */}}
{{- define "n8n.pvc" -}}
{{- if or (not .Values.main.persistence.enabled) (eq .Values.main.persistence.type "emptyDir") -}}
          emptyDir: {}
{{- else if and .Values.main.persistence.enabled .Values.main.persistence.existingClaim -}}
          persistentVolumeClaim:
            claimName: {{ .Values.main.persistence.existingClaim }}
{{- else if and .Values.main.persistence.enabled (eq .Values.main.persistence.type "dynamic")  -}}
          persistentVolumeClaim:
            claimName: {{ include "n8n.fullname" . }}
{{- end }}
{{- end }}


{{/* Create environment variables from yaml tree */}}
{{- define "toEnvVars" -}}
    {{- $prefix := "" }}
    {{- if .prefix }}
        {{- $prefix = printf "%s_" .prefix }}
    {{- end }}
    {{- range $key, $value := .values }}
        {{- if kindIs "map" $value -}}
            {{- dict "values" $value "prefix" (printf "%s%s" $prefix ($key | upper)) "isSecret" $.isSecret | include "toEnvVars" -}}
        {{- else -}}
            {{- if $.isSecret -}}
{{ $prefix }}{{ $key | upper }}: {{ $value | toString | b64enc }}{{ "\n" }}
            {{- else -}}
{{ $prefix }}{{ $key | upper }}: {{ $value | toString | quote }}{{ "\n" }}
            {{- end -}}
        {{- end -}}
    {{- end -}}
{{- end }}


{{/* Validate Valkey/Redis configuration when webhooks are enabled*/}}
{{- define "n8n.validateValkey" -}}
{{- $envVars := fromYaml (include "toEnvVars" (dict "values" .Values.main.config "prefix" "")) -}}
{{- if and .Values.webhook.enabled (not $envVars.QUEUE_BULL_REDIS_HOST) -}}
{{- fail "Webhook processes rely on Valkey. Please set a Redis/Valkey host when webhook.enabled=true" -}}
{{- end -}}
{{- end -}}


{{/* Determine whether internal task runners are enabled */}}
{{- define "n8n.taskRunnerEnabled" -}}
{{- $preset := default "" .Values.preset -}}
{{- $mode := default "" .Values.main.taskRunners.mode -}}
{{- if or (eq $preset "taskrunners") (eq $mode "internal") -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}


{{/* Default environment variables for internal task runners */}}
{{- define "n8n.mainPresetEnv" -}}
{{- $env := dict -}}
{{- if eq (include "n8n.taskRunnerEnabled" . | trim) "true" -}}
  {{- $_ := set $env "N8N_RUNNERS_ENABLED" (dict "value" "true") -}}
  {{- $_ := set $env "OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS" (dict "value" "false") -}}
  {{- $_ := set $env "EXECUTIONS_MODE" (dict "value" (default "queue" .Values.main.taskRunners.executionsMode)) -}}
{{- end -}}
{{- toYaml $env -}}
{{- end -}}


{{/* Merge preset driven environment variables with user provided ones */}}
{{- define "n8n.mainMergedExtraEnv" -}}
{{- $presetRaw := include "n8n.mainPresetEnv" . -}}
{{- $preset := dict -}}
{{- if $presetRaw -}}
  {{- $preset = fromYaml $presetRaw -}}
{{- end -}}
{{- $user := default (dict) .Values.main.extraEnv -}}
{{- $merged := merge (deepCopy $preset) (deepCopy $user) -}}
{{- toYaml $merged -}}
{{- end -}}


{{/* Validate task runner and webhook combinations */}}
{{- define "n8n.validateTaskRunners" -}}
{{- if and .Values.webhook.enabled (not .Values.worker.enabled) (eq (include "n8n.taskRunnerEnabled" . | trim) "true") -}}
{{- fail "External webhook pods rely on external workers when task runners are enabled. Disable webhooks or enable workers." -}}
{{- end -}}
{{- end -}}


