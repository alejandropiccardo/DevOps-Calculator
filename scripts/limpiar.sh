#!/usr/bin/env bash
# Borra todos los recursos creados por iniciar.sh.
#   ./scripts/limpiar.sh          -> borra recursos, deja minikube
#   ./scripts/limpiar.sh --todo   -> ademas borra el cluster minikube
set -uo pipefail
cd "$(dirname "$0")/.."
kubectl delete -f falco/prueba-falco.yaml -f kyverno/pruebas/ --ignore-not-found 2>/dev/null
kubectl delete -f k8s/ -f monitoring/ --ignore-not-found
kubectl delete -f kyverno/politicas/ --ignore-not-found
helm uninstall falco -n falco 2>/dev/null
kubectl delete ns falco --ignore-not-found
kubectl delete -f https://github.com/kyverno/kyverno/releases/download/v1.19.2/install.yaml --ignore-not-found 2>/dev/null
if [ "${1:-}" = "--todo" ]; then minikube delete; fi
echo "Recursos eliminados."
