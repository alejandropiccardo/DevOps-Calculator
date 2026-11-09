#!/usr/bin/env bash
# Corre Semgrep y actualiza reports/semgrep-report.txt.
# Conserva el historial de arriba (antes/despues y justificaciones) y reemplaza
# solo la seccion de la ultima ejecucion, asi se puede correr varias veces.
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no reescribir rutas como /src

REPORTE=reports/semgrep-report.txt
MARCA="# LAB 4 - ULTIMA EJECUCION"
SALIDA="$(docker run --rm -v "$(pwd -W 2>/dev/null || pwd):/src" -w /src semgrep/semgrep:1.181.1 \
  semgrep scan \
  --config semgrep/reglas-python.yaml \
  --config p/python --config p/dockerfile --config p/kubernetes \
  --config p/secrets --config p/security-audit \
  --metrics=off app k8s monitoring 2>&1)"
CODIGO=$?

sed -i "/^$MARCA/,\$d" "$REPORTE"
{
  echo "$MARCA"
  echo "# Fecha: $(date '+%Y-%m-%d %H:%M')"
  echo "# Reglas propias: semgrep/reglas-python.yaml + rulesets p/python, p/dockerfile,"
  echo "#                 p/kubernetes, p/secrets, p/security-audit"
  echo "# Codigo de salida de semgrep: $CODIGO"
  echo
  echo "$SALIDA"
} >> "$REPORTE"
echo "$SALIDA" | tail -15
echo "Reporte actualizado: $REPORTE"
exit "$CODIGO"
