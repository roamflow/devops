# Grafana Loki & Promtail Pod Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Grafana Loki (Monolithic) and Promtail (DaemonSet) into the existing `monitoring` stack to provide centralized Kubernetes pod logging with a 7-day retention policy and automated Grafana datasource provisioning.

**Architecture:** Extend the existing Helm chart in `apps/monitoring` by adding `loki` and `promtail` as chart dependencies. Configure Loki in Monolithic mode using a dedicated 5Gi `local-path` PersistentVolumeClaim and compactor retention. Configure Promtail as a DaemonSet across all nodes (`roamflow-1` and `roamflow-2`) to ingest containerd CRI logs from `/var/log/pods`. Provision Loki as a native datasource in Grafana.

**Tech Stack:** Helm 4, Kubernetes (k3s v1.34.4), Grafana Loki 6.x, Promtail 6.x, Grafana 13.x, Argo CD.

**Spec:** `docs/superpowers/specs/2026-09-28-loki-logging-design.md`

## Global Constraints

- Storage: `local-path` StorageClass, 5Gi volume size.
- Retention: 168h (7 days), managed by Loki compactor.
- Resource footprint: Monolithic mode only, no distributed microservices, no memcached cache.
- Multi-tenancy: `auth_enabled: false`.
- Target namespace: `monitoring`.

---

### Task 1: Update Chart Dependencies and Lockfile

**Files:**
- Modify: `devops/apps/monitoring/Chart.yaml`
- Modify: `devops/apps/monitoring/Chart.lock`

**Interfaces:**
- Produces: Chart dependencies for `kube-prometheus-stack`, `loki` (6.27.0), and `promtail` (6.16.6) packaged and locked.

- [ ] **Step 1: Update `devops/apps/monitoring/Chart.yaml` with Loki and Promtail dependencies**

```yaml
apiVersion: v2
name: monitoring-stack
description: Prometheus, Grafana, and Loki Monitoring & Logging Stack for Kubernetes
type: application
version: 1.1.0
appVersion: "v0.93.1"
dependencies:
  - name: kube-prometheus-stack
    version: "88.5.3"
    repository: https://prometheus-community.github.io/helm-charts
  - name: loki
    version: "6.27.0"
    repository: https://grafana.github.io/helm-charts
  - name: promtail
    version: "6.16.6"
    repository: https://grafana.github.io/helm-charts
```

- [ ] **Step 2: Update Helm dependencies and build lockfile**

Run:
```bash
helm dependency update devops/apps/monitoring
```
Expected: Downloads `loki` and `promtail` charts into local archive cache and updates `Chart.lock`.

- [ ] **Step 3: Remove generated `.tgz` files from `charts/` directory if created**

Note: Argo CD builds dependencies dynamically from `Chart.lock` and Git repository keeps only `Chart.yaml` and `Chart.lock` (ignore `.tgz` binaries or clean `charts/` subfolder).

- [ ] **Step 4: Commit dependencies update**

```bash
git add devops/apps/monitoring/Chart.yaml devops/apps/monitoring/Chart.lock
git commit -m "feat(monitoring): add loki and promtail helm chart dependencies"
```

---

### Task 2: Configure Loki, Promtail, and Grafana Datasource in `values.yaml`

**Files:**
- Modify: `devops/apps/monitoring/values.yaml`

**Interfaces:**
- Consumes: Dependencies from Task 1.
- Produces: Declarative configuration for Loki storage/retention, Promtail DaemonSet, and Grafana Datasource.

- [ ] **Step 1: Add Grafana additionalDatasources configuration to `kube-prometheus-stack`**

In `devops/apps/monitoring/values.yaml` under `kube-prometheus-stack.grafana`:
```yaml
    additionalDataSources:
      - name: Loki
        type: loki
        access: proxy
        url: http://monitoring-loki:3100
        isDefault: false
        jsonData:
          maxLines: 1000
```

- [ ] **Step 2: Append `loki` configuration block to `values.yaml`**

```yaml
loki:
  deploymentMode: Monolithic
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  storage_config:
    filesystem:
      directory: /var/loki/chunks
  singleBinary:
    replicas: 1
    persistence:
      enabled: true
      size: 5Gi
      storageClassName: local-path
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 768Mi
  compactor:
    retention_enabled: true
    retention_delete_delay: 2h
    delete_request_store: filesystem
  limits_config:
    retention_period: 168h
  chunksCache:
    enabled: false
  resultsCache:
    enabled: false
  gateway:
    enabled: false
  lokiCanary:
    enabled: false
  test:
    enabled: false
```

- [ ] **Step 3: Append `promtail` configuration block to `values.yaml`**

```yaml
promtail:
  config:
    clients:
      - url: http://monitoring-loki:3100/loki/api/v1/push
  resources:
    requests:
      cpu: 20m
      memory: 32Mi
    limits:
      cpu: 100m
      memory: 96Mi
  tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/control-plane
      operator: Exists
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
      operator: Exists
```

- [ ] **Step 4: Test rendering template locally**

Run:
```bash
helm template monitoring devops/apps/monitoring -f devops/apps/monitoring/values.yaml > /dev/null
```
Expected: Command exits with code 0 without any syntax or template error.

- [ ] **Step 5: Commit `values.yaml` configuration**

```bash
git add devops/apps/monitoring/values.yaml
git commit -m "feat(monitoring): configure loki monolithic, promtail daemonset, and grafana datasource"
```

---

### Task 3: Push to Git and Synchronize via Argo CD

**Files:**
- Git repository `main` branch

**Interfaces:**
- Consumes: Commits from Task 1 and Task 2.
- Produces: Deployed workloads on the live cluster.

- [ ] **Step 1: Push commits to remote Git repository**

Run:
```bash
git push origin main
```
Expected: Commits pushed successfully to `origin/main`.

- [ ] **Step 2: Trigger and wait for Argo CD synchronization**

Run:
```bash
kubectl -n argocd get application monitoring -o jsonpath='{.status.sync.status}'
```
Wait until status is `Synced` and health is `Healthy`.

---

### Task 4: Cluster & Grafana End-to-End Verification

**Files:** None (Cluster runtime verification)

- [ ] **Step 1: Verify Loki StatefulSet/Pod and PVC**

Run:
```bash
kubectl get pods,pvc -n monitoring -l app.kubernetes.io/name=loki
```
Expected: Pod `monitoring-loki-0` is `1/1 Running`, PVC is `Bound` on `local-path` with capacity `5Gi`.

- [ ] **Step 2: Verify Promtail DaemonSet pods across both nodes**

Run:
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail -o wide
```
Expected: 2 pods running, one on `roamflow-1` and one on `roamflow-2`.

- [ ] **Step 3: Query Loki labels API**

Run:
```bash
kubectl exec -n monitoring deploy/monitoring-grafana -c grafana -- wget -qO- http://monitoring-loki:3100/loki/api/v1/labels
```
Expected: JSON response with status `success` containing labels `["app", "container", "namespace", "node_name", "pod"]`.

- [ ] **Step 4: Verify Grafana Explore LogQL Query**

Run a sample LogQL query through Loki's query API:
```bash
kubectl exec -n monitoring deploy/monitoring-grafana -c grafana -- wget -qO- 'http://monitoring-loki:3100/loki/api/v1/query?query=%7Bnamespace%3D%22monitoring%22%7D&limit=5'
```
Expected: Returns latest log entries from `monitoring` namespace.
