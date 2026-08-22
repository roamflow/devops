#!/usr/bin/env bash
set -euo pipefail

echo "==> Creating argocd namespace..."
kubectl create namespace argocd 2>/dev/null || true

echo "==> Installing Argo CD..."
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Configuring Argo CD Server for insecure/proxy mode (behind Traefik TLS)..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd

echo "==> Applying Argo CD Ingress..."
kubectl apply -f infrastructure/argocd/ingress.yaml

echo "==> Waiting for Argo CD components to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

echo "==> Retrieving initial admin password..."
sleep 5
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Password not generated yet")
echo "========================================="
echo "Argo CD URL: https://argocd.duylai.duckdns.org"
echo "Username:    admin"
echo "Password:    $PASS"
echo "========================================="
