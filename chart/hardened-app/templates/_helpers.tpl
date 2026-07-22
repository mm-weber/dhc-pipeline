{{- define "hardened-app.name" -}}hardened-app{{- end -}}

{{- define "hardened-app.labels" -}}
app.kubernetes.io/name: {{ include "hardened-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "hardened-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hardened-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
