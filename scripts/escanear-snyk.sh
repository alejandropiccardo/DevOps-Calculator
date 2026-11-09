#!/usr/bin/env bash
# Escanea las dependencias con Snyk y guarda el resultado en reports/snyk-report.txt.
# Requiere un token de una cuenta de Snyk (gratis):
#   https://app.snyk.io/account  ->  Auth Token
#   SNYK_TOKEN=xxxx ./scripts/escanear-snyk.sh
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no reescribir rutas como /app

if [ -z "${SNYK_TOKEN:-}" ]; then
  echo "Falta SNYK_TOKEN. Sacalo de https://app.snyk.io/account" >&2
  exit 2
fi

REPORTE=reports/snyk-report.txt
RAIZ="$(pwd -W 2>/dev/null || pwd)"
# Se baja aparte para que el progreso de la descarga no ensucie el reporte.
docker pull -q snyk/snyk:python-3.12 >/dev/null
PEOR=0
{
  echo "# Escaneo de dependencias con Snyk - $(date '+%Y-%m-%d %H:%M')"
  for v in v1 v2; do
    echo
    echo "================================================================================"
    echo "\$ snyk test --file=requirements.txt --package-manager=pip   (app/$v)"
    echo "================================================================================"
    docker run --rm -e SNYK_TOKEN -v "$RAIZ/app/$v:/app" -w /app snyk/snyk:python-3.12 \
      snyk test --file=requirements.txt --package-manager=pip 2>&1
    CODIGO=$?
    echo "# Codigo de salida: $CODIGO  (0 = sin vulnerabilidades, 1 = hay, 2/3 = error)"
    [ "$CODIGO" -gt "$PEOR" ] && PEOR=$CODIGO
  done
} | tee "$REPORTE"
echo "Reporte guardado en $REPORTE"
