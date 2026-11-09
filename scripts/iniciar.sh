#!/usr/bin/env bash
# Levanta todo: minikube, imagenes, Kyverno, Falco, app + Prometheus + Grafana,
# y genera trafico para poblar los dashboards.
set -euo pipefail
cd "$(dirname "$0")/.."

minikube status >/dev/null 2>&1 || minikube start --cpus=4 --memory=6144
docker build -t calculadora:1.2 app/v1
docker build -t calculadora:2.2 app/v2
minikube image load calculadora:1.2
minikube image load calculadora:2.2

./scripts/instalar-operadores.sh
kubectl apply -f k8s/ -f monitoring/
for d in calculadora-blue calculadora-green prometheus grafana; do
  kubectl rollout status deploy/$d --timeout=300s
done

./scripts/generar-carga.sh
echo "Grafana:    $(minikube service grafana --url | head -1)   (admin / devops2026)"
echo "Prometheus: $(minikube service prometheus --url | head -1)"
