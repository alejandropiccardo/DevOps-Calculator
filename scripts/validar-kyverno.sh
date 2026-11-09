#!/usr/bin/env bash
# Aplica los manifiestos conformes y no conformes y guarda la evidencia en
# reports/kyverno-validation.log.
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=reports/kyverno-validation.log
{
  echo "# Validacion de politicas de Kyverno - $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "## 1. Politicas instaladas"
  echo '$ kubectl get validatingpolicies'
  kubectl get validatingpolicies
  echo
  echo "## 2. Manifiestos NO conformes: tienen que ser rechazados"
  echo '$ kubectl apply -f kyverno/pruebas/no-conforme.yaml'
  kubectl apply -f kyverno/pruebas/no-conforme.yaml 2>&1
  echo '$ kubectl get pods prueba-latest prueba-sin-recursos prueba-root prueba-privilegiado'
  kubectl get pods prueba-latest prueba-sin-recursos prueba-root prueba-privilegiado 2>&1
  echo '$ kubectl get deploy prueba-todo-mal'
  kubectl get deploy prueba-todo-mal 2>&1
  echo
  echo "## 3. Control positivo: un Pod conforme es aceptado"
  echo '$ kubectl apply -f kyverno/pruebas/conforme.yaml'
  kubectl apply -f kyverno/pruebas/conforme.yaml 2>&1
  kubectl delete -f kyverno/pruebas/conforme.yaml --ignore-not-found 2>&1
  echo
  echo "## 4. Los manifiestos del proyecto cumplen las politicas (dry-run en el servidor)"
  echo '$ kubectl apply --dry-run=server -f k8s/ -f monitoring/'
  kubectl apply --dry-run=server -f k8s/ -f monitoring/ 2>&1
} | tee "$LOG"
echo "Evidencia guardada en $LOG"
