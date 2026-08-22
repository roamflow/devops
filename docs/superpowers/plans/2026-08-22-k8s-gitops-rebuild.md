# Kubernetes GitOps Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean legacy workloads in-place, bootstrap Argo CD & Bitnami Sealed Secrets on K3s, structure the GitOps repository, and deploy declarative application manifests with automatic sync.

**Architecture:** We use an in-place cleanup to preserve healthy K3s core and cert-manager, deploy Argo CD as the GitOps engine pulling from the GitHub repository, use Bitnami Sealed Secrets for safe secret storage in Git, and leverage K3s Traefik for SSL termination.

**Tech Stack:** K3s v1.34, Argo CD, Bitnami Sealed Secrets, Traefik v3, cert-manager, Kustomize, Helm, Git.

**Spec:** `docs/superpowers/specs/2026-08-22-k8s-gitops-rebuild-design.md`

## Global Constraints

- Preserve healthy nodes (`roamflow-1`, `roamflow-2`), CoreDNS, and Traefik Ingress.
- Keep `ClusterIssuer/letsencrypt-prod` in `cert-manager`.
- Base domain: `*.duylai.duckdns.org`.
- StorageClass: `local-path` (`rancher.io/local-path`).
- No plain plaintext secrets committed into Git — all secrets must use `SealedSecret`.

---

### Task 1: In-Place Cleanup of Legacy Workloads

**Files:**
- Create: `bootstrap/01-cleanup-legacy.sh`

**Interfaces:**
- Consumes: Existing helm releases (`gitea`, `gitea-runner`, `vikunja`, `headlamp`) and namespaces.
- Produces: Clean cluster state containing only `kube-system`, `cert-manager`, `default`.

- [ ] **Step 1: Write cleanup script**

```bash
mkdir -p bootstrap
cat << 'EOF' > bootstrap/01-cleanup-legacy.sh
#!/usr/bin/env bash
set -euo pipefail

echo "==> Uninstalling legacy helm releases..."
helm uninstall gitea gitea-runner -n gitea 2>/dev/null || true
helm uninstall vikunja -n vikunja 2>/dev/null || true
helm uninstall headlamp -n headlamp 2>/dev/null || true

echo "==> Deleting legacy namespaces and lingering PVCs..."
kubectl delete namespace gitea vikunja headlamp --timeout=60s 2>/dev/null || true

echo "==> Cluster cleaned successfully."
EOF
chmod +x bootstrap/01-cleanup-legacy.sh
```

- [ ] **Step 2: Execute cleanup script and verify**

Run: `bash bootstrap/01-cleanup-legacy.sh`  
Verify: `kubectl get ns` and `kubectl get pods -A`  
Expected: Only `kube-system`, `cert-manager`, `default` namespaces exist.

---

### Task 2: Install Bitnami Sealed Secrets Controller & Backup Key

**Files:**
- Create: `bootstrap/02-install-sealed-secrets.sh`

**Interfaces:**
- Consumes: Clean cluster.
- Produces: Sealed Secrets controller running in `kube-system`, `kubeseal` CLI installed, master secret key backed up.

- [ ] **Step 1: Write Sealed Secrets installation script**

```bash
cat << 'EOF' > bootstrap/02-install-sealed-secrets.sh
#!/usr/bin/env bash
set -euo pipefail

echo "==> Deploying Bitnami Sealed Secrets Controller..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.28.0/sealed-secrets-controller.yaml

echo "==> Waiting for controller to be ready..."
kubectl rollout status deployment/sealed-secrets-controller -n kube-system --timeout=120s

echo "==> Backing up master encryption key locally..."
mkdir -p .secrets
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > .secrets/sealed-secrets-master-key.yaml
echo "Master key backed up to .secrets/sealed-secrets-master-key.yaml"
EOF
chmod +x bootstrap/02-install-sealed-secrets.sh
```

- [ ] **Step 2: Execute installation script and verify**

Run: `bash bootstrap/02-install-sealed-secrets.sh`  
Verify: `kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets`  
Expected: `sealed-secrets-controller` pod is `1/1 Running`.

---

### Task 3: Install Argo CD & Configure Ingress with TLS

**Files:**
- Create: `bootstrap/03-install-argocd.sh`
- Create: `infrastructure/argocd/ingress.yaml`

**Interfaces:**
- Consumes: Sealed Secrets controller, Traefik, cert-manager.
- Produces: Argo CD running in `argocd` namespace, accessible at `https://argocd.duylai.duckdns.org`.

- [ ] **Step 1: Write Argo CD Ingress manifest**

```yaml
mkdir -p infrastructure/argocd
cat << 'EOF' > infrastructure/argocd/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - argocd.duylai.duckdns.org
    secretName: argocd-tls-secret
  rules:
  - host: argocd.duylai.duckdns.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF
```

- [ ] **Step 2: Write Argo CD installation script**

```bash
cat << 'EOF' > bootstrap/03-install-argocd.sh
#!/usr/bin/env bash
set -euo pipefail

echo "==> Creating argocd namespace..."
kubectl create namespace argocd 2>/dev/null || true

echo "==> Installing Argo CD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Configuring Argo CD Server for insecure/proxy mode (behind Traefik TLS)..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd

echo "==> Applying Argo CD Ingress..."
kubectl apply -f infrastructure/argocd/ingress.yaml

echo "==> Waiting for Argo CD components to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

echo "==> Retrieving initial admin password..."
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Argo CD Admin Password: $PASS"
EOF
chmod +x bootstrap/03-install-argocd.sh
```

- [ ] **Step 3: Execute installation and verify**

Run: `bash bootstrap/03-install-argocd.sh`  
Verify: `kubectl get pods -n argocd` and `kubectl get ingress -n argocd`  
Expected: All pods Running and Ingress created.

---

### Task 4: Git Repository Scaffolding & GitOps Base Structure

**Files:**
- Create: `.gitignore`
- Create: `clusters/roamflow/root-app.yaml`
- Create: `clusters/roamflow/kustomization.yaml`

- [ ] **Step 1: Create .gitignore ensuring secrets and local keys are ignored**

```text
cat << 'EOF' > .gitignore
.secrets/
*.key
*.pem
.env
EOF
```

- [ ] **Step 2: Initialize Git repository**

```bash
git init
git add .gitignore bootstrap/ infrastructure/
git commit -m "chore: bootstrap k3s GitOps foundation with Argo CD and Sealed Secrets"
```

- [ ] **Step 3: Create Argo CD Root Application (App-of-Apps pattern)**

```yaml
mkdir -p clusters/roamflow
cat << 'EOF' > clusters/roamflow/root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-apps
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/laiduy98/devops.git # Update with exact repo URL
    targetRevision: main
    path: apps
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

---

### Task 5: Declarative Application Manifests (`apps/`)

**Files:**
- Create: `apps/headlamp/` (Dashboard)
- Create: `apps/vikunja/` (Task Management)
- Create: `apps/gitea/` (Git Server)

- [ ] **Step 1: Create declarative manifests for Headlamp**
- [ ] **Step 2: Create declarative manifests for Vikunja**
- [ ] **Step 3: Create declarative manifests for Gitea**
- [ ] **Step 4: Commit manifests to Git**

---

### Task 6: Final Verification & GitOps Sync

- [ ] **Step 1: Verify all Argo CD Applications are Synced and Healthy**
- [ ] **Step 2: Verify TLS certificates on `*.duylai.duckdns.org`**
- [ ] **Step 3: Update documentation and walkthrough**
