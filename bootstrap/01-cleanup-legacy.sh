#!/usr/bin/env bash
set -euo pipefail

echo "==> Uninstalling legacy helm releases..."
helm uninstall gitea gitea-runner -n gitea 2>/dev/null || true
helm uninstall vikunja -n vikunja 2>/dev/null || true
helm uninstall headlamp -n headlamp 2>/dev/null || true

echo "==> Deleting legacy namespaces and lingering PVCs..."
kubectl delete namespace gitea vikunja headlamp --timeout=60s 2>/dev/null || true

echo "==> Cluster cleaned successfully."
