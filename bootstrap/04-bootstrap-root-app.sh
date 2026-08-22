#!/usr/bin/env bash
set -euo pipefail

echo "==> Applying Root Argo CD Application..."
kubectl apply -f clusters/roamflow/root-app.yaml

echo "==> Waiting for Argo CD to sync Root Application..."
kubectl get applications -n argocd
