#!/usr/bin/env bash
# Mide tamano y capas de las imagenes y corre Dive en modo CI.
# El resultado se resume a mano en reports/image-analysis.md; la salida completa
# queda en reports/dive-output.txt.
set -uo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no reescribir /var/run/docker.sock

DIVE_IMAGE=wagoodman/dive:v0.13.1
SALIDA=reports/dive-output.txt
{
  echo "# Analisis de imagenes - $(date '+%Y-%m-%d %H:%M')  |  $DIVE_IMAGE"
  for t in 1.2 2.2; do
    echo
    echo "================================================================================"
    echo "calculadora:$t"
    echo "================================================================================"
    echo "Tamano (bytes): $(docker image inspect "calculadora:$t" --format '{{.Size}}')"
    echo "Capas del filesystem: $(docker image inspect "calculadora:$t" --format '{{len .RootFS.Layers}}')"
    echo
    echo "\$ docker history calculadora:$t"
    docker history "calculadora:$t" --format 'table {{.Size}}\t{{.CreatedBy}}' --no-trunc | cut -c1-120
    echo
    echo "\$ dive --ci calculadora:$t"
    docker run --rm -e CI=true -v /var/run/docker.sock:/var/run/docker.sock "$DIVE_IMAGE" "calculadora:$t" 2>&1
  done
} | sed 's/\x1b\[[0-9;]*m//g' | tee "$SALIDA"
echo "Salida guardada en $SALIDA"
