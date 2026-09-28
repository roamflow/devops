# Grafana Loki & Promtail Pod Logging Stack Design

**Date:** 2026-09-28  
**Status:** Approved  
**Target Cluster:** Personal Kubernetes Cluster (`roamflow`)  
**Target Namespace:** `monitoring`  
**GitOps Engine:** Argo CD (`monitoring` application)  

---

## 1. Overview & Objectives

Expand the existing `monitoring` stack (currently providing metrics via Prometheus, Node Exporter, Kube-State-Metrics, and Grafana) to include centralized **Pod Logging** across the cluster.

### Key Objectives
- **Centralized Pod Log Collection**: Automatically collect `stdout` and `stderr` logs from all running pods across both cluster nodes (`roamflow-1` and `roamflow-2`).
- **Low Footprint / Resource Efficient**: Optimize for 2-node ARM64 Oracle Cloud Always Free instance (4 vCPU, 24GB RAM total) by running Loki in `Monolithic` mode with local filesystem storage and minimal memory consumption (<850MB RAM total overhead).
- **Automated Retention Management**: Retain logs for 7 days (`168h`) backed by a dedicated `5Gi` `local-path` PersistentVolumeClaim, managed by Loki's compactor to prevent disk exhaustion.
- **Native Grafana Integration**: Automatically provision Loki as a primary log datasource in Grafana so users can seamlessly browse logs in Grafana **Explore** and correlate metrics with logs.
- **Declarative GitOps Management**: Manage everything declaratively within the existing Helm chart in `apps/monitoring`, continuously synchronized by Argo CD.

---

## 2. Architecture & Data Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Nodes                                │
│                                                                        │
│   Pods (stdout/stderr) ──► K3s containerd ──► /var/log/pods/*.log       │
│                                                     │                  │
│                                                     ▼                  │
│                                      ┌──────────────────────────────┐  │
│                                      │     Promtail (DaemonSet)     │  │
│                                      │  - CRI parser                │  │
│                                      │  - Label enrichment          │  │
│                                      └──────────────┬───────────────┘  │
│                                                     │                  │
│                        HTTP Push (:3100/loki/api/v1/push)              │
│                                                     ▼                  │
│                                      ┌──────────────────────────────┐  │
│                                      │      Loki (Monolithic)       │  │
│                                      │  - Single binary             │  │
│                                      │  - Compactor (7d retention)  │  │
│                                      │  - Storage: 5Gi local-path   │  │
│                                      └──────────────┬───────────────┘  │
│                                                     │                  │
│                         LogQL Query (:3100)         │                  │
│                                                     ▼                  │
│                                      ┌──────────────────────────────┐  │
│                                      │           Grafana            │  │
│                                      │  (Explore View / Dashboards) │  │
│                                      └──────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

### Data Flow Breakdown
1. **Log Generation**: Containers write to standard output/error. K3s containerd runtime writes these to `/var/log/pods/<namespace>_<pod>_<uid>/<container>/<retry>.log` in CRI format (`<timestamp> <stream> <flag> <content>`).
2. **Collection & Labeling**: **Promtail** daemon instances run on every node (`roamflow-1` and `roamflow-2`). They discover pod log files via host mount, apply CRI parsing stages, enrich entries with Kubernetes labels (`namespace`, `pod`, `container`, `app`), and buffer streams.
3. **Ingestion & Indexing**: Promtail batches and pushes compressed logs over HTTP to `http://monitoring-loki:3100/loki/api/v1/push`. Loki indexes the labels and writes chunk files to the local persistent volume.
4. **Retention & Compaction**: Loki's internal compactor aggregates chunks and enforces a 7-day retention policy (`retention_period: 168h`), automatically purging expired chunks.
5. **Visualization**: Grafana queries Loki over the internal cluster service (`http://monitoring-loki:3100`). Users query logs using LogQL in the **Explore** tab (e.g. `{namespace="authentik"}` or `{app="changedetection"}`).

---

## 3. Helm Chart Dependencies (`apps/monitoring/Chart.yaml`)

We extend `apps/monitoring/Chart.yaml` to include upstream Helm chart dependencies from Grafana's repository (`https://grafana.github.io/helm-charts`):

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

---

## 4. Configuration Specification (`apps/monitoring/values.yaml`)

### 4.1 Loki Configuration (`loki:`)
- **Deployment Mode**: `Monolithic` (SingleBinary running all services inside a single Pod/StatefulSet).
- **Authentication**: `auth_enabled: false` (single tenant for internal homelab cluster).
- **Storage**:
  - `storage.type: filesystem`
  - `storage_config.filesystem.directory: /var/loki/chunks`
- **Persistence**:
  - Enabled: `true`
  - StorageClass: `local-path`
  - Capacity: `5Gi`
- **Compactor & Retention**:
  - `compactor.retention_enabled: true`
  - `limits_config.retention_period: 168h` (7 days)
  - `compactor.delete_request_store: filesystem`
- **Memory & Resource Optimization**:
  - `gateway.enabled: false` (not needed in monolithic mode)
  - `chunksCache.enabled: false` (disables memcached to save RAM)
  - `resultsCache.enabled: false` (disables memcached)
  - `lokiCanary.enabled: false`
  - `test.enabled: false`
  - Requests: `100m CPU`, `256Mi Memory`
  - Limits: `500m CPU`, `768Mi Memory`

### 4.2 Promtail Configuration (`promtail:`)
- **Deployment Type**: `DaemonSet`
- **Target URL**: `http://monitoring-loki:3100/loki/api/v1/push`
- **Tolerations**: Tolerates control-plane/master taints to ensure coverage across all nodes:
  ```yaml
  tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/control-plane
      operator: Exists
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
      operator: Exists
  ```
- **Resource Limits per Pod**:
  - Requests: `20m CPU`, `32Mi Memory`
  - Limits: `100m CPU`, `96Mi Memory`

### 4.3 Grafana Datasource Provisioning
Add Loki to `kube-prometheus-stack.grafana.additionalDataSources`:
```yaml
kube-prometheus-stack:
  grafana:
    additionalDataSources:
      - name: Loki
        type: loki
        access: proxy
        url: http://monitoring-loki:3100
        isDefault: false
        jsonData:
          maxLines: 1000
```

---

## 5. Verification & Acceptance Criteria

| Step | Target Resource | Verification Command | Expected Output |
| :--- | :--- | :--- | :--- |
| 1 | Loki Pod & PVC | `kubectl get pods,pvc -n monitoring -l app.kubernetes.io/name=loki` | Pod `Running (1/1)`, PVC `5Gi Bound` |
| 2 | Promtail DaemonSet | `kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail -o wide` | 2/2 Pods `Running`, 1 on `roamflow-1`, 1 on `roamflow-2` |
| 3 | Log Ingestion API | `kubectl exec -n monitoring deploy/monitoring-grafana -c grafana -- wget -qO- http://monitoring-loki:3100/loki/api/v1/labels` | JSON response containing `["app","container","namespace","node_name","pod",...]` |
| 4 | Grafana Datasource | Open `https://grafana.duylai.duckdns.org/explore` | Loki appears in datasource selector; queries such as `{namespace="monitoring"}` return log streams |
