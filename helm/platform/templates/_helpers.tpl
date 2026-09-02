{{- define "platform.labels" -}}
app.kubernetes.io/part-of: operations-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

