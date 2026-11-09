#!/usr/bin/env bash
# Dispara la regla propia de Falco (wget en un contenedor, sin shell) y guarda
# la alerta en reports/falco-event.log.
set -euo pipefail
cd "$(dirname "$0")/.."
LOG=reports/falco-event.log
kubectl delete -f falco/prueba-falco.yaml --ignore-not-found >/dev/null
kubectl apply -f falco/prueba-falco.yaml
sleep 15
{
  echo "# Evento de Falco - $(date '+%Y-%m-%d %H:%M')"
  echo "# Accion: Pod prueba-falco ejecuta wget (falco/prueba-falco.yaml). No abre shell."
  echo "# Regla: Herramienta de red ejecutada en contenedor (falco/values.yaml, customRules)."
  echo '$ kubectl -n falco logs ds/falco -c falco | grep "Herramienta de red"'
  kubectl -n falco logs ds/falco -c falco | grep "Herramienta de red" | grep prueba-falco
} | tee "$LOG"
