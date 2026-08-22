#!/usr/bin/env bash
set -euo pipefail

KUBESEAL_VERSION="0.28.0"

echo "==> Checking kubeseal CLI..."
if ! command -v kubeseal &> /dev/null; then
    echo "Installing kubeseal CLI v${KUBESEAL_VERSION} to ~/.local/bin/kubeseal..."
    mkdir -p ~/.local/bin
    curl -sSL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" | tar -xz -C ~/.local/bin kubeseal
    chmod +x ~/.local/bin/kubeseal
fi

echo "==> Deploying Bitnami Sealed Secrets Controller (v${KUBESEAL_VERSION})..."
kubectl apply -f "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/controller.yaml"

echo "==> Waiting for Sealed Secrets controller to be ready..."
kubectl rollout status deployment/sealed-secrets-controller -n kube-system --timeout=120s

echo "==> Backing up master encryption key locally..."
mkdir -p .secrets
# Wait a few seconds for the controller to generate its active key
sleep 5
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > .secrets/sealed-secrets-master-key.yaml
echo "==> Master key backed up to .secrets/sealed-secrets-master-key.yaml"
