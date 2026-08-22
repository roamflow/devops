# Kubernetes Cluster GitOps Rebuild Design

**Date:** 2026-08-22  
**Target Cluster:** Personal Kubernetes Cluster (`roamflow`)  
**Nodes:** `roamflow-1` (control-plane), `roamflow-2` (worker)  
**Distribution:** k3s (`v1.34.4+k3s1`)  
**Domain:** `*.duylai.duckdns.org`  

---

## 1. Overview & Objectives

Transform the manually configured personal Kubernetes cluster into a fully declarative, automated **GitOps-driven** environment.
- **In-place Cleanup**: Remove legacy, untracked app workloads (`gitea`, `vikunja`, `headlamp`) without wiping the healthy base K3s cluster.
- **GitOps Engine**: Deploy **Argo CD** to watch the GitHub repository (`devops`) and continuously reconcile workloads and configurations.
- **Secret Management**: Deploy **Bitnami Sealed Secrets** to enable safe, encrypted secret storage inside the public/private Git repository.
- **Ingress & TLS**: Leverage K3s's built-in **Traefik v3** and existing **cert-manager** (`ClusterIssuer/letsencrypt-prod`) for automatic HTTPS on DuckDNS domains.
- **Single Source of Truth**: All applications, configs, and sealed secrets are defined declaratively in Git.

---

## 2. Architecture & Components

```
                      ┌──────────────────────────────────────────────┐
                      │              GitHub Repository               │
                      │  (Infrastructure, Apps, Sealed Secrets YAML)  │
                      └──────────────────────┬───────────────────────┘
                                             │
                                   git push  │ (Argo CD auto-sync)
                                             ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (roamflow-1 & roamflow-2 on k3s)                                 │
│                                                                                      │
│   ┌──────────────────────────┐         ┌─────────────────────────────────────────┐   │
│   │         Argo CD          ├────────►│ Deployments / StatefulSets / Services   │   │
│   │ (GitOps & Web Dashboard) │         │ (Gitea, Vikunja, Headlamp, etc.)        │   │
│   └──────────────────────────┘         └─────────────────────────────────────────┘   │
│                ▲                                            ▲                        │
│                │                                            │ decrypts to            │
│   ┌────────────┴─────────────┐                 ┌────────────┴────────────┐           │
│   │ Traefik Ingress + TLS    │                 │ Sealed Secrets Operator │           │
│   │ (DuckDNS + cert-manager) │                 │ (Decrypts Git YAMLs)    │           │
│   └──────────────────────────┘                 └─────────────────────────┘           │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### Core Components
1. **K3s Base Infrastructure**:
   - Traefik v3 (Ingress Controller + ServiceLB on port 80/443).
   - Local-Path StorageClass (`rancher.io/local-path`).
   - Cert-Manager v1.19.3 + `letsencrypt-prod` ClusterIssuer.
2. **GitOps Tier**:
   - **Argo CD**: Installed in `argocd` namespace, exposed via Traefik Ingress at `https://argocd.duylai.duckdns.org`.
   - **Bitnami Sealed Secrets**: Installed in `kube-system` / `sealed-secrets` namespace to decrypt `SealedSecret` manifests.
3. **Application Tier**:
   - Organized in `apps/` directory (e.g., `apps/gitea`, `apps/vikunja`, `apps/headlamp`).
   - Managed via Argo CD "App-of-Apps" or root application.

---

## 3. Repository Structure (`devops`)

```text
devops/
├── bootstrap/                          # One-time bootstrap scripts
│   ├── 01-cleanup-legacy.sh            # In-place removal of old apps/namespaces/PVCs
│   ├── 02-install-sealed-secrets.sh    # Installs Bitnami Sealed Secrets controller + CLI setup
│   ├── 03-install-argocd.sh            # Installs Argo CD + Ingress configuration
│   └── 04-bootstrap-root-app.sh        # Connects Argo CD to the GitHub repository
├── clusters/
│   └── roamflow/                       # Root Argo CD Application definition
│       ├── root-app.yaml               # App-of-apps root application
│       └── kustomization.yaml
├── infrastructure/                     # Cluster-wide infrastructure managed by GitOps
│   ├── cert-manager/
│   │   └── cluster-issuer.yaml         # Let's Encrypt production ClusterIssuer
│   ├── middlewares/
│   │   └── redirect-https.yaml         # Traefik HTTP -> HTTPS redirection
│   └── sealed-secrets/
│       └── release.yaml                # Sealed secrets operator manifest
└── apps/                               # Application manifests / Kustomize / Helm
    ├── argocd/                         # Self-managed Argo CD manifests & ingress
    │   ├── ingress.yaml
    │   └── kustomization.yaml
    ├── headlamp/                       # Headlamp dashboard
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── ingress.yaml
    │   └── kustomization.yaml
    ├── vikunja/                        # Vikunja task management
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── pvc.yaml
    │   ├── ingress.yaml
    │   └── kustomization.yaml
    └── gitea/                          # Gitea Git service
        ├── values.yaml                 # Declarative Helm values / manifests
        └── kustomization.yaml
```

---

## 4. Execution Workflow

1. **Phase 1: In-place Cleanup**
   - Uninstall legacy helm releases: `gitea`, `gitea-runner`, `vikunja`, `headlamp`.
   - Delete stale namespaces & associated PVCs (`gitea`, `vikunja`, `headlamp`).
2. **Phase 2: Bootstrap Sealed Secrets & Argo CD**
   - Install Bitnami Sealed Secrets controller.
   - Backup the Sealed Secrets master encryption private key locally (`sealed-secrets-key.yaml`).
   - Install Argo CD (standard manifests), configure Ingress with TLS (`https://argocd.duylai.duckdns.org`).
3. **Phase 3: Repository Scaffolding & Manifests**
   - Initialize Git repository and commit directory structure.
   - Build declarative Kustomize/Helm manifests for `infrastructure` and `apps`.
4. **Phase 4: Argo CD Root Application Sync**
   - Deploy `root-app.yaml` to Argo CD.
   - Verify all apps auto-sync, get Let's Encrypt certificates, and reach Healthy state.

---

## 5. Security & Disaster Recovery

- **Master Key Backup**: Sealed Secrets private encryption key is backed up securely offline. If the cluster is ever rebuilt from scratch, restoring this single key allows immediate decryption of all committed secrets.
- **GitOps Drift Detection**: Any out-of-band changes to cluster resources are automatically overwritten to match the Git state.
