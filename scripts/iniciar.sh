#!/usr/bin/env bash
# Levanta todo: minikube, imagenes, Kyverno, Falco, app + Prometheus + Grafana,
# y genera trafico para poblar los dashboards.
set -euo pipefail
cd "$(dirname "$0")/.."

minikube status >/dev/null 2>&1 || minikube start --cpus=4 --memory=6144
docker build -t calculadora:1.2 app/v1
docker build -t calculadora:2.2 app/v2
# minikube image load no reemplaza una imagen con el mismo tag: se borra antes.
minikube ssh -- docker rmi -f calculadora:1.2 calculadora:2.2 >/dev/null 2>&1 || true
minikube image load calculadora:1.2
minikube image load calculadora:2.2

./scripts/instalar-operadores.sh
kubectl apply -f k8s/ -f monitoring/
for d in calculadora-blue calculadora-green prometheus grafana; do
  kubectl rollout status deploy/$d --timeout=300s
done

./scripts/generar-carga.sh
echo "Todo arriba. Para ver Grafana y Prometheus: ./scripts/abrir-monitoreo.sh"
