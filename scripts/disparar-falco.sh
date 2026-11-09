#!/usr/bin/env bash
# Dispara la regla estandar "Search Private Keys or Passwords" (sin shell) y guarda
# la alerta en reports/falco-event.log.
set -euo pipefail
cd "$(dirname "$0")/.."
LOG=reports/falco-event.log
kubectl delete -f falco/prueba-falco.yaml --ignore-not-found >/dev/null
kubectl apply -f falco/prueba-falco.yaml
sleep 15
{
  echo "# Evento de Falco - $(date '+%Y-%m-%d %H:%M')"
  echo "# Accion: el Pod prueba-falco ejecuta find /etc -name id_rsa (falco/prueba-falco.yaml).
# Simula a un atacante buscando claves privadas. No abre ningun shell."
  echo "# Regla: Search Private Keys or Passwords (reglas por defecto de Falco, prioridad Warning)."
  echo '$ kubectl -n falco logs ds/falco -c falco | grep "Search Private Keys"'
  kubectl -n falco logs ds/falco -c falco | grep "Search Private Keys" | grep prueba-falco
} | tee "$LOG"
