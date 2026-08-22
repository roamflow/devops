# Personal Kubernetes Cluster (`roamflow`)

This document summarizes the architecture, infrastructure, networking, and deployed workloads for the personal Kubernetes cluster.

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

| Service | Namespace | Hostname | Target Backend | Ports | TLS Certificate |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Gitea** | `gitea` | `https://gitea.duylai.duckdns.org` | `gitea-http:3000` | 80, 443 | `gitea-tls-secret` |
| **Gitea SSH** | `gitea` | `gitea.duylai.duckdns.org:30222` | `gitea-ssh:22` | NodePort `30222` | N/A (SSH) |
| **Headlamp** | `headlamp` | `https://headlamp.duylai.duckdns.org` | `headlamp:80` | 80, 443 | `headlamp-tls` |
| **Vikunja** | `vikunja` | `https://tasks.duylai.duckdns.org` | `vikunja:3456` | 80, 443 | `tasks-tls` |

---

## 4. Deployed Workloads & Helm Releases

### Helm Releases Summary

| Release Name | Namespace | Chart | App Version | Status | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`gitea`** | `gitea` | `gitea-12.5.0` | `1.25.4` | deployed | Self-hosted Git server |
| **`gitea-runner`** | `gitea` | `actions-0.0.3` | `0.261.3` | deployed | Gitea Actions CI/CD Runner (`act-runner`) |
| **`vikunja`** | `vikunja` | `vikunja-2.0.0` | `1.0.0` | deployed | Task and project management |
| **`headlamp`** | `headlamp` | `headlamp-0.44.0` | `0.44.0` | deployed | Kubernetes Web UI / Dashboard |
| **`cert-manager`** | `cert-manager` | `cert-manager-v1.19.3` | `v1.19.3` | deployed | TLS certificate automation |
| **`traefik`** | `kube-system` | `traefik-38.0.201+up38.0.2` | `v3.6.6` | deployed | Ingress controller & reverse proxy |

---

## 5. Workload Architecture Details

### A. Gitea Ecosystem (`gitea` namespace)
- **Web App**: `gitea` Deployment running on `roamflow-2`.
- **Database**: Bitnami PostgreSQL High Availability (`gitea-postgresql-ha`) with `pgpool` load balancer and replicated StatefulSets (`10Gi` PVC per instance).
- **Cache / Key-Value**: Valkey Cluster (Redis-compatible, 3 StatefulSet replicas with `8Gi` PVC each).
- **CI/CD Runner**: `gitea-runner-actions-act-runner-0` Daemon/Stateful pod running on `roamflow-1` for executing Gitea Actions workflows.
- **Storage**: `gitea-shared-storage` (`10Gi` PVC).

### B. Vikunja Task Management (`vikunja` namespace)
- **Application**: `vikunja` Deployment running on `roamflow-2`.
- **Storage**:
  - `vikunja-data` (`2Gi` PVC)
  - `vikunja-database` (`2Gi` PVC)

### C. Headlamp Cluster Dashboard (`headlamp` namespace)
- **Application**: `headlamp` Deployment running on `roamflow-1`.
- **Authentication**: Configured with OIDC and ServiceAccount access tokens (`headlamp-admin-token`, `headlamp-user-token`).

### D. Core Cluster Services (`kube-system` & `cert-manager`)
- **Metrics Server**: Running on `roamflow-1` for resource monitoring (`kubectl top`).
- **CoreDNS**: In-cluster DNS provider running on `roamflow-2`.
- **Local Path Provisioner**: Host-path dynamic storage provisioner on `roamflow-1`.
- **Cert-Manager**: Controller, CA injector, and Webhook components managing ACME certificates.

---

## 6. Storage & Volume Configuration

Dynamic volume provisioning is provided by Rancher's `local-path` StorageClass (`WaitForFirstConsumer` binding mode):

| Persistent Volume Claim | Namespace | Size | Access Mode | Bound To |
| :--- | :--- | :--- | :--- | :--- |
| `gitea-shared-storage` | `gitea` | 10 GiB | RWO | Shared Git repositories and assets |
| `data-gitea-postgresql-ha-postgresql-0..2` | `gitea` | 3 x 10 GiB | RWO | PostgreSQL HA database nodes |
| `valkey-data-gitea-valkey-cluster-0..2` | `gitea` | 3 x 8 GiB | RWO | Valkey cluster persistence |
| `data-act-runner-gitea-runner-actions-act-runner-0` | `gitea` | 1 GiB | RWO | Gitea Actions runner cache |
| `vikunja-data` | `vikunja` | 2 GiB | RWO | Vikunja files/uploads |
| `vikunja-database` | `vikunja` | 2 GiB | RWO | Vikunja database storage |

---

## 7. Common Operational Commands

```bash
# Check cluster node status and resources
kubectl get nodes -o wide
kubectl top nodes

# Check pod resource utilization across all namespaces
kubectl top pods -A

# Check all ingress routes and TLS certificates
kubectl get ingress,certificates -A

# View installed Helm releases
helm list -A

# Inspect cluster events and issues
kubectl get events -A --sort-by='.lastTimestamp'
```
