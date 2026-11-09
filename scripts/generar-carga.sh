#!/usr/bin/env bash
# Version bash de generar-carga.ps1: trafico contra la calculadora para poblar
# Grafana (RPS, latencia, metricas de negocio) y disparar las alertas.
#   ./scripts/generar-carga.sh [URL] [VALIDAS] [INVALIDAS]
# Sin URL, abre un port-forward al Service mientras dura la carga.
set -euo pipefail
URL="${1:-}"
if [ -z "$URL" ]; then
  kubectl port-forward svc/calculadora 18080:80 >/dev/null 2>&1 &
  PF=$!
  trap 'kill "$PF" 2>/dev/null' EXIT
  URL=http://127.0.0.1:18080
  for _ in $(seq 1 20); do curl -s "$URL/health" >/dev/null && break; sleep 1; done
fi
VALIDAS="${2:-60}"
INVALIDAS="${3:-12}"

INFO="$(curl -s "$URL/")"
echo "Version activa: $INFO"
OK=("suma?a=2&b=3" "resta?a=9&b=4" "multiplicacion?a=6&b=7" "division?a=10&b=2")
MAL=("division?a=1&b=0" "suma?a=abc&b=3")
if echo "$INFO" | grep -q '"raiz"'; then OK+=("raiz?a=16"); MAL+=("raiz?a=-9"); fi

echo "Enviando $VALIDAS operaciones validas..."
for ((i = 0; i < VALIDAS; i++)); do curl -s "$URL/${OK[$((i % ${#OK[@]}))]}" >/dev/null; done
echo "Enviando $INVALIDAS operaciones invalidas..."
for ((i = 0; i < INVALIDAS; i++)); do curl -s "$URL/${MAL[$((i % ${#MAL[@]}))]}" >/dev/null; done
echo "Listo. Las alertas tardan ~45 s. Para ver Grafana y Prometheus: ./scripts/abrir-monitoreo.sh"
