#!/usr/bin/env bash
# Version bash de generar-carga.ps1: trafico contra la calculadora para poblar
# Grafana (RPS, latencia, metricas de negocio) y disparar las alertas.
#   ./scripts/generar-carga.sh [URL] [VALIDAS] [INVALIDAS]
# Sin URL, usa "minikube service calculadora --url".
set -euo pipefail
URL="${1:-$(minikube service calculadora --url | head -1)}"
VALIDAS="${2:-60}"
INVALIDAS="${3:-12}"

INFO="$(curl -s "$URL/")"
echo "Version activa: $INFO"
OK=("suma?a=2&b=3" "resta?a=9&b=4" "multiplicacion?a=6&b=7" "division?a=10&b=2")
MAL=("division?a=1&b=0" "suma?a=abc&b=3")
if echo "$INFO" | grep -q '"raiz"'; then OK+=("raiz?a=16"); MAL+=("raiz?a=-9"); fi

echo "Enviando $VALIDAS operaciones validas..."
for ((i = 0; i < VALIDAS; i++)); do curl -s -o /dev/null "$URL/${OK[$((i % ${#OK[@]}))]}"; done
echo "Enviando $INVALIDAS operaciones invalidas..."
for ((i = 0; i < INVALIDAS; i++)); do curl -s -o /dev/null "$URL/${MAL[$((i % ${#MAL[@]}))]}"; done
echo "Listo. Alertas en ~45 s: Prometheus :30090/alerts | Grafana :30030 (admin / devops2026)"
