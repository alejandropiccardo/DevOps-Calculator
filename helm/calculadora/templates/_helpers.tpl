{{/*
Nombre base de los recursos. Se usa el nombre del release para que el chart se
pueda instalar mas de una vez en el mismo namespace.
*/}}
{{- define "calculadora.fullname" -}}
{{- .Values.nombreApp | default .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels comunes a todos los recursos.
*/}}
{{- define "calculadora.labels" -}}
app.kubernetes.io/name: {{ include "calculadora.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Labels de seleccion. Son las que mira el Service y las que distinguen los dos
entornos; se mantienen cortas y estables porque cambiarlas obligaria a recrear
los Deployments (spec.selector es inmutable).
*/}}
{{- define "calculadora.selectorLabels" -}}
app: {{ include "calculadora.fullname" . }}
{{- end -}}
