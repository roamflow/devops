# Personal Kubernetes Cluster (`roamflow`) & GitOps Repository

This document summarizes the architecture, infrastructure, networking, and GitOps workflow for the personal Kubernetes cluster.

---

## 1. Cluster Overview

- **Distribution**: [k3s](https://k3s.io/) (`v1.34.4+k3s1`)
- **Control Plane Endpoint**: `https://92.5.22.64:6443`
- **Cluster Architecture**: Multi-node ARM64 (`aarch64`)
- **Infrastructure Provider**: Oracle Cloud Infrastructure (OCI Always Free Tier)
- **Container Runtime**: containerd (`2.1.5-k3s1`)
- **Default Storage Class**: `local-path` (`rancher.io/local-path`)
- **Ingress Controller**: Traefik v3 (`v3.6.6`) with K3s Klipper ServiceLB (`svclb-traefik`)
- **Certificate Management**: [cert-manager](https://cert-manager.io/) (`v1.19.3`) with Let's Encrypt ACME HTTP-01
- **GitOps Engine**: [Argo CD](https://argo-cd.readthedocs.io/) with automatic synchronization
- **Secrets Management**: [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) (`kubeseal`)
- **Base Domain**: `*.duylai.duckdns.org` (DuckDNS)

---

## 2. Nodes & Compute Specifications

The cluster consists of 2 nodes totaling **4 ARM64 OCPUs** and **~24 GB RAM**:

| Node Name | Role | Arch | CPU | Memory | Internal IP | OS / Kernel | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`roamflow-1`** | `control-plane` (master) | `arm64` | 2 vCPU | 12 GB | `10.0.0.46` | Ubuntu 24.04.4 LTS (`6.17.0-1009-oracle`) | Ready |
| **`roamflow-2`** | `worker` (agent) | `arm64` | 2 vCPU | 12 GB | `10.0.0.136` | Ubuntu 24.04.4 LTS (`6.17.0-1014-oracle`) | Ready |

### Cluster Network CIDRs
- **Pod Network CIDR**: `10.42.0.0/16`
- **Service Network CIDR**: `10.43.0.0/16`
- **CoreDNS Service IP**: `10.43.0.10`

---

## 3. Ingress & Exposed Services

All public endpoints are routed through Traefik using automatic Let's Encrypt TLS certificates issued via `ClusterIssuer/letsencrypt-prod`:

| Service | Namespace | Hostname | Target Backend | Ports | TLS Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Argo CD** | `argocd` | `https://argocd.duylai.duckdns.org` | `argocd-server:80` | 80, 443 | Valid Let's Encrypt TLS |
| **Headlamp** | `headlamp` | `https://headlamp.duylai.duckdns.org` | `headlamp:80` | 80, 443 | Valid Let's Encrypt TLS |
| **Vikunja** | `vikunja` | `https://tasks.duylai.duckdns.org` | `vikunja:3456` | 80, 443 | Valid Let's Encrypt TLS |
| **Gitea** | `gitea` | `https://gitea.duylai.duckdns.org` | `gitea-http:3000` | 80, 443 | Valid Let's Encrypt TLS |
| **Authentik SSO** | `authentik` | `https://auth.duylai.duckdns.org` | `authentik-server:80` | 80, 443 | Valid Let's Encrypt TLS |
| **Stirling PDF** | `stirling-pdf` | `https://pdf.duylai.duckdns.org` | `stirling-pdf-stirling-pdf-chart:8080` | 80, 443 | Valid Let's Encrypt TLS |
| **Grafana Dashboards** | `monitoring` | `https://grafana.duylai.duckdns.org` | `monitoring-grafana:80` | 80, 443 | Valid Let's Encrypt TLS |
| **MLflow Tracking** | `mlflow` | `https://mlflow.duylai.duckdns.org` | `mlflow:5000` | 80, 443 | Valid Let's Encrypt TLS (Authentik SSO) |
| **Dagster Platform** | `dagster` | `https://dagster.duylai.duckdns.org` | `dagster-webserver:3000` | 80, 443 | Valid Let's Encrypt TLS (Authentik SSO) |

---

## 4. GitOps Repository Structure

This repository is the single source of truth for cluster workloads and configurations:

```text
devops/
├── bootstrap/                          # One-time bootstrap scripts
│   ├── 01-cleanup-legacy.sh            # In-place cleanup script
│   ├── 02-install-sealed-secrets.sh    # Installs Sealed Secrets controller + CLI
│   ├── 03-install-argocd.sh            # Installs Argo CD + Ingress
│   └── 04-bootstrap-root-app.sh        # Connects Root Application to GitHub
├── clusters/
│   └── roamflow/                       # Argo CD Applications (App-of-Apps)
│       ├── root-app.yaml               # Root Application entrypoint
│       ├── infrastructure.yaml         # Argo CD app for core infra
│       ├── headlamp.yaml               # Argo CD app for Headlamp
│       ├── vikunja.yaml                # Argo CD app for Vikunja
│       ├── gitea.yaml                  # Argo CD app for Gitea Helm chart
│       ├── authentik.yaml              # Argo CD app for Authentik SSO
│       ├── stirling-pdf.yaml           # Argo CD app for Stirling-PDF
│       ├── monitoring.yaml             # Argo CD app for Prometheus & Grafana
│       ├── mlflow.yaml                 # Argo CD app for MLflow Tracking Server
│       ├── dagster.yaml                # Argo CD app for Dagster Data Platform
│       └── kustomization.yaml
├── infrastructure/                     # Cluster-wide components
│   ├── cert-manager/
│   │   └── cluster-issuer.yaml         # Let's Encrypt ClusterIssuer
│   ├── middlewares/
│   │   └── redirect-https.yaml         # Traefik HTTP->HTTPS redirection
│   ├── argocd/
│   │   └── ingress.yaml                # Argo CD Ingress
│   └── kustomization.yaml
└── apps/                               # Declarative workload manifests
    ├── authentik/                      # Authentik Identity & SSO Platform
    ├── dagster/                        # Dagster Webserver, Daemon & Postgres
    ├── gitea/                          # Gitea Helm Chart & Values
    ├── headlamp/                       # Headlamp Dashboard (Kustomize)
    ├── mlflow/                         # MLflow Tracking Server & SQLite
    ├── monitoring/                     # Prometheus, Grafana, Node Exporter
    ├── stirling-pdf/                   # Stirling-PDF Tool (Helm Chart)
    └── vikunja/                        # Vikunja Task Management (Kustomize)
```

---

## 5. Secrets Management Workflow (Bitnami Sealed Secrets)

To safely store secrets in Git:

1. Create a standard local secret YAML (do **not** commit):
   ```bash
   kubectl create secret generic my-secret --from-literal=password=supersecret --dry-run=client -o yaml > secret.yaml
   ```
2. Encrypt it with `kubeseal`:
   ```bash
   kubeseal -f secret.yaml -w sealed-secret.yaml --controller-name=sealed-secrets-controller --controller-namespace=kube-system
   ```
3. Commit `sealed-secret.yaml` to Git. Argo CD and the in-cluster controller will automatically decrypt it.

> [!IMPORTANT]
> The master encryption key is safely backed up in `.secrets/sealed-secrets-master-key.yaml` (ignored by git).

---

## 6. Access & Credentials

- **Argo CD**: `https://argocd.duylai.duckdns.org`
  - **Username**: `admin`
  - **Password**: Retrieve with:
    ```bash
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    ```
- **Headlamp Dashboard**: `https://headlamp.duylai.duckdns.org`
  - **Login Token**: Retrieve with:
    ```bash
    kubectl get secret -n headlamp headlamp-admin-token -o jsonpath="{.data.token}" | base64 -d
    ```
- **Vikunja**: `https://tasks.duylai.duckdns.org`

---

## 7. Common Operational Commands

```bash
# Check all pods and sync status
kubectl get pods -A
kubectl get applications -n argocd

# Check all ingress routes and TLS certificates
kubectl get ingress,certificates -A

# Test building all kustomize manifests
kubectl kustomize infrastructure/
kubectl kustomize clusters/roamflow/
```
