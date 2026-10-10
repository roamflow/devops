{{/*
Chart name, truncated to the 63-char limit of Kubernetes names.
*/}}
{{- define "model-serving.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified resource name: <release>-<chart>, unless the release name
already contains the chart name.
*/}}
{{- define "model-serving.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Labels set on every resource. Includes the selector labels.
*/}}
{{- define "model-serving.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "model-serving.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels. Immutable on a Deployment, so keep this set minimal and
never put the version here.
*/}}
{{- define "model-serving.selectorLabels" -}}
app.kubernetes.io/name: {{ include "model-serving.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Container image reference.
*/}}
{{- define "model-serving.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}
