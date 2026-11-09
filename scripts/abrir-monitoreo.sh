#!/usr/bin/env bash
# Abre Grafana y Prometheus en localhost. Queda corriendo hasta Ctrl+C.
set -euo pipefail
kubectl port-forward svc/prometheus 9090:9090 &
PF=$!
trap 'kill "$PF" 2>/dev/null' EXIT
echo "Prometheus: http://127.0.0.1:9090"
echo "Grafana:    http://127.0.0.1:3000  (admin / devops2026)"
kubectl port-forward svc/grafana 3000:3000
