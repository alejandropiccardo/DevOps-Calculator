#!/usr/bin/env bash
# Instala los operadores/controladores del cluster: Kyverno y Falco.
set -euo pipefail
cd "$(dirname "$0")/.."

echo ">> Kyverno v1.19.2"
kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.19.2/install.yaml || true
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=300s

echo ">> Falco (chart 9.2.1)"
helm upgrade --install falco falco --repo https://falcosecurity.github.io/charts \
  --version 9.2.1 -n falco --create-namespace -f falco/values.yaml
kubectl -n falco rollout status ds/falco --timeout=300s

echo ">> Politicas de Kyverno"
kubectl apply -f kyverno/politicas/
