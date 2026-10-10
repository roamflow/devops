# MLOps Platform Engineering: Daily Comprehensive Recap (2026-10-10)
> **Target Audience:** Senior / Staff MLOps Engineer Interview Preparation (Turo Paris Stack: Kubernetes, Ray, MLflow, Dagster, Docker, Terraform)  
> **Infrastructure Environment:** 2-Node ARM64 k3s cluster (`roamflow`) on Oracle Cloud Infrastructure (OCI Always Free), GitOps-managed via Argo CD.

---

## 1. Executive Summary

Today we engineered, deployed, and validated an enterprise-grade, end-to-end MLOps platform from bare Kubernetes primitives up to production ML observability. Over the course of the day, we completed **Step 1 (Model Serving & Helm Chart)**, **Step 7 (PostgreSQL MLflow Backend)**, **Step 3 (Train ──► Registry ──► Serve Lifecycle)**, and **Step 6 (Full-Stack Observability & Dual-Layer Drift Detection)**.

### Architectural High-Level Flow
```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                   THE ROAMFLOW MLOPS PLATFORM                          │
└────────────────────────────────────────────────────────────────────────────────────────┘

    [Data Warehouse / Raw Data]
                 │
                 ▼
       ┌───────────────────┐
       │   DAGSTER CORE    │  (Control Plane: Webserver + Daemon + Postgres)
       └─────────┬─────────┘
                 │ (gRPC Code Server - User Code Location)
                 ▼
       ┌───────────────────┐
       │   `ml-pipelines`  │  Asset 1: iris_data (Load & Train/Test Split)
       │   (K8s Code Pod)  │  Asset 2: train_and_register_iris_model (Acc >= 0.90 Quality Gate)
       └─────────┬─────────┘  Asset 3: detect_data_drift (Offline 2-Sample KS-Test)
                 │
                 │ (HTTP Artifact Proxy & REST API)
                 ▼
       ┌───────────────────┐
       │   MLFLOW SERVER   │  (Backend: PostgreSQL 16 Alpine + 5Gi PVC)
       │    v3.17.0        │  (Artifact Storage: Local-Path PVC via HTTP Proxy)
       │  (Model Registry) │  Registered Model: `iris-classifier` with Alias `@Production`
       └─────────┬─────────┘
                 │
                 │ (Dynamic Lazy Pull at Pod Startup)
                 ▼
       ┌───────────────────┐
       │   `model-serving` │  FastAPI + scikit-learn runtime (Docker ARM64)
       │    (Kubernetes)   │  Rolling buffer (200 reqs) -> Live KS-Test p-values
       └─────────┬─────────┘  RED Metrics + ML Compute Latency + Label Distribution
                 │
                 │ (Prometheus Scrape via ServiceMonitor: 15s interval)
                 ▼
       ┌───────────────────┐
       │    PROMETHEUS     │  Prometheus Operator with MatchLabels: release=monitoring
       └─────────┬─────────┘
                 │
                 │ (Grafana Sidecar Auto-Provisioning via ConfigMap)
                 ▼
       ┌───────────────────┐
       │      GRAFANA      │  Dashboard UID: `ml-model-serving-iris` (15 Production Panels)
       │    DASHBOARDS     │  - Live P-Value Table with conditional red/green thresholds
       └───────────────────┘  - E2E vs pure model.predict() latency breakdown
                              - Label Shift / Prediction Distribution Donut Chart
```

---

## 2. Core Pillars & Engineering Accomplishments

### Pillar I: Production ML Serving Layer (`model-serving`)
* **Technology Stack:** FastAPI, `uv`, `prometheus-client`, `scikit-learn`, `scipy`.
* **Zero-Downtime Container Lifecycle:**
  * **Liveness Probe (`/health`):** Verifies the process is alive; completely isolated from model loading or network dependencies so downstream hiccups never trigger cascading restart loops.
  * **Readiness Probe (`/ready`):** Returns HTTP 200 only after the ML model is fully loaded into application memory. Prevents premature traffic routing by kube-proxy.
  * **Startup Probe:** Protects heavy model download and initialization phases from aggressive liveness timeouts.
* **Helm Chart from Scratch:**
  * Authored clean Kubernetes templates: `Deployment`, `Service`, `Ingress`, `HorizontalPodAutoscaler` (HPA), `ServiceMonitor`, and `ConfigMap` for Grafana.
  * **HPA Best Practice:** Intentionally omitted hardcoded `replicas` in `Deployment.spec` to prevent Helm rollouts from fighting the Horizontal Pod Autoscaler.
  * **Resource Sizing:** Left CPU `limits` unconstrained while defining baseline `requests` to eliminate Linux CFS quota CPU throttling on latency-sensitive inference threads.
* **Continuous Delivery Pipeline (3-Tier Separation of Concerns):**
  * `test` (ruff + pytest) ──► `build` (Docker buildx native ARM64 with GHCR push) ──► `promote` (Scoped SSH Deploy Key updates `image.tag` in `devops` Helm values).
  * Promotes immutable tags combining SemVer + Git Short SHA (e.g., `v0.1.0-51c6c21`).

### Pillar II: Production MLflow Architecture (SQLite to PostgreSQL Migration)
* **Problem:** MLflow originally ran on SQLite with a file-level database lock. SQLite fails immediately in production:
  1. Concurrent training runs trigger `sqlite3.OperationalError: database is locked`.
  2. Forced K8s deployment strategy to `Recreate`, guaranteeing downtime during upgrades.
* **Solution:**
  * Deployed dedicated PostgreSQL 16 Alpine instance with 5Gi persistent storage and SealedSecrets credentials.
  * Updated MLflow tracking URI to `postgresql+psycopg2://...`.
  * Enabled zero-downtime `RollingUpdate` with multi-worker concurrency.
* **Artifact Reverse Proxy Pattern:**
  * Configured `--artifacts-destination /mlflow/artifacts --serve-artifacts`.
  * Allows serving pods and training pipelines in external namespaces to download and upload model binaries through MLflow's HTTP server without dispersing cloud storage IAM credentials.

### Pillar III: Modern Data & ML Pipeline Orchestration (`ml-pipelines`)
* **Modular Dagster Architecture:**
  * Decoupled the Dagster Control Plane (Webserver + Daemon) from User Code Locations.
  * Packaged `ml-pipelines` as an independent gRPC code server communicating over port 4000.
  * Data scientists can iterate on models, push code, and deploy new container versions without restarting core platform infrastructure.
* **Software-Defined Assets:**
  * `iris_data`: Ingests dataset and produces train/test splits.
  * `train_and_register_iris_model`: Trains candidate model, executes quality evaluation gate, logs parameters to MLflow, and promotes to registry.
  * `detect_data_drift`: Performs statistical checks against baseline data.
* **Evaluation Quality Gate:**
  * Automated threshold enforcement (`MIN_ACCURACY_THRESHOLD = 0.90`).
  * If accuracy $< 0.90$, candidate model promotion is aborted and tagged `@Candidate_Rejected`. The existing `@Production` model remains untouched.
* **MLflow 3.x Mutable Aliases:**
  * Transitioned from deprecated MLflow stages (`Staging`, `Production`) to mutable pointer aliases (`@Production`).

### Pillar IV: Dual-Layer ML Observability & Drift Detection
Today we answered the critical design question: **"Where and how should Data Drift be monitored in production?"** We established a dual-layer strategy:

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                               DUAL-LAYER DRIFT ARCHITECTURE                           │
├───────────────────────────────────────────┬───────────────────────────────────────────┤
│ Layer 1: Online Proxy Drift (Real-Time)   │ Layer 2: Offline Deep Drift (Scheduled)   │
├───────────────────────────────────────────┼───────────────────────────────────────────┤
│ • Run in: `model-serving` (FastAPI)       │ • Run in: `ml-pipelines` (Dagster)        │
│ • Frequency: Real-time (per request)     │ • Frequency: Hourly / Daily batch job     │
│ • Data: Rolling in-memory window (200 req)│ • Data: Historic Data Lake (millions rows)│
│ • Tooling: Prometheus + Grafana          │ • Tooling: Dagster Asset Catalog / MLflow │
│ • Primary Metric: Output Label Shift &    │ • Primary Metric: 2-Sample KS-Test, PSI,  │
│   online KS-test p-values on live buffer  │   Wasserstein distance on all features    │
│ • Alerting: Prometheus Alertmanager (<1m) │ • Action: Auto-trigger pipeline retrain   │
└───────────────────────────────────────────┴───────────────────────────────────────────┘
```

1. **Online KS-Test Implementation in Serving:**
   * Maintained reference baseline training features in memory.
   * Captured incoming request vectors in an in-memory `collections.deque(maxlen=200)`.
   * Evaluated `scipy.stats.ks_2samp` per feature when buffer $\ge 10$ samples.
   * Exposed Prometheus gauges: `model_serving_feature_drift_p_value` and `model_serving_feature_drift_detected`.
2. **Production Grafana Dashboard-as-Code:**
   * ConfigMap labeled `grafana_dashboard: "1"`, monitored by `grafana-sc-dashboard` sidecar.
   * Automatically provisioned 15 panels:
     * **RED Metrics:** Throughput (QPS), P95 Latency, Error Rate.
     * **Latency Breakdown:** E2E HTTP Latency vs Pure Model `predict()` compute time.
     * **Label Shift:** Real-time prediction class ratios (Setosa, Versicolor, Virginica).
     * **P-Value Table:** Live feature-by-feature p-values with green/red conditional color thresholding at $\alpha = 0.05$.
     * **P-Value Timeseries:** Temporal curves with horizontal threshold marker at $0.05$.

---

## 3. Key Technical Decisions & Debugging Gotchas

### 1. High Cardinality Threat in Prometheus TSDB
* **Design Decision:** Never emit raw continuous feature floats or user IDs as Prometheus labels.
* **Rationale:** Each unique combination of label keys and values creates a distinct time series in Prometheus TSDB. Emitting float values causes a time-series explosion, rapidly exhausting RAM.
* **Our Solution:** We emit static feature names as labels (`feature="sepal_length"`) and record the float p-value as the gauge **value**, not a label.

### 2. SQLAlchemy 2.0 Driver Conflict with Postgres (`NOTIFY`)
* **Problem:** Dagster Daemon crashed with `Internal Server Error: connection is closed` during Postgres event communication.
* **Root Cause:** SQLAlchemy 2.0+ defaults to `psycopg` (v3). Unlike `psycopg2`, `psycopg3` prepares all statements with positional parameter syntax (`$1`), which is rejected by PostgreSQL's `NOTIFY run_events, $1` syntax.
* **Fix:** Explicitly configured dialect `postgresql+psycopg2://...` in connection string and ensured `psycopg2-binary` was bundled in the container.

### 3. Decoupling Model Weights from Container Images
* **Anti-Pattern:** Baking `.pkl` or `.onnx` model files directly into Docker images (`COPY model.pkl .`).
* **Why it fails at scale:**
  * Docker images balloon to gigabytes.
  * Retraining a model requires a full Docker build, security scan, and CI/CD push.
  * Cannot roll back model logic independently of serving application logic.
* **Best Practice Implemented:** Serving container image is purely runtime code. Model binary is dynamically pulled at startup from MLflow Model Registry via `@Production` alias.

---

## 4. Interview Cheat Sheet: High-Impact Talking Points

### Q1: "How do you distinguish latency bottlenecks in ML serving?"
> *"I decompose telemetry into two distinct histograms: End-to-End HTTP request duration and isolated model compute duration (`model.predict()`). This allows me to immediately differentiate between Python ASGI/Pydantic serialization bottlenecks, network I/O, event-loop blocking, and actual tensor compute saturation on the CPU/GPU."*

### Q2: "Why can't SQLite be used for MLflow in production?"
> *"SQLite relies on database-level file locks. Under multi-worker concurrency or parallel distributed training runs, writes conflict with `database is locked` errors. Furthermore, SQLite forces Kubernetes deployments into a `Recreate` strategy, guaranteeing downtime during maintenance. PostgreSQL provides Multi-Version Concurrency Control (MVCC) with row-level locks, unlocking seamless horizontal scaling and zero-downtime `RollingUpdate` deployments."*

### Q3: "How do you detect Data Drift before it degrades business revenue?"
> *"I implement a dual-layer observability architecture. In the real-time serving tier, I track output label shift and execute online two-sample Kolmogorov-Smirnov tests across sliding request windows, exposing p-values via Prometheus gauges to trigger immediate alerts if input features collapse. In the background batch tier, Dagster executes deep statistical drift suites (KS-test, PSI, Wasserstein distance) across historical data warehouses to decide whether to trigger automated model retraining."*

---

## 5. STAR Interview Stories (English)

### Story 1: Automated Model Train-to-Serve GitOps Promotion
* **Situation:** In our Kubernetes MLOps platform, training pipelines in Dagster and real-time model serving in FastAPI were decoupled across distinct namespaces, lacking an automated model lifecycle promotion flow.
* **Task:** Build an automated end-to-end pipeline where training models are seamlessly logged, governed with production aliases, and dynamically served without baking weights into container images.
* **Action:** Configured MLflow 3.17 as an HTTP Artifact Proxy backed by PostgreSQL 16 and a 10Gi PVC. Authored Dagster software-defined assets with `FilesystemIOManager` and MLflow Client SDK to automatically promote winning candidate models to the `@Production` alias upon passing a 90% accuracy quality gate. Updated FastAPI serving to lazily fetch `models:/iris-classifier@Production` via cluster-internal endpoints with proper startup and readiness probes.
* **Result:** Achieved a fully automated model train-to-serve cycle with zero manual weight transfers, verified live external inference at sub-50ms latency, and preserved cloud-agnostic portability without vendor lock-in.

### Story 2: Real-Time ML Observability and Statistical Drift Detection
* **Situation:** Traditional infrastructure telemetry (CPU, RAM, network) fails to detect model degradation, inference bottlenecks, or feature distribution shifts in production.
* **Task:** Build an enterprise-grade ML observability system for our Kubernetes model serving layer, capturing RED metrics, isolated inference compute latency, and real-time statistical drift p-values on Grafana.
* **Action:** Instrumented the FastAPI serving app with `prometheus-client`, exposing Prometheus RED metrics alongside custom ML metrics (`inference_duration_seconds`, `batch_size`, and `predictions_total` labeled by predicted class). Implemented an in-memory rolling buffer running live Kolmogorov-Smirnov tests (`scipy.stats.ks_2samp`) against baseline distributions to publish live p-values. Provisioned a Prometheus Operator `ServiceMonitor` and an automated Grafana Dashboard ConfigMap loaded via sidecar.
* **Result:** Established sub-second dashboard visibility into P95/P99 latency breakdowns and feature-level statistical drift, with live color-coded p-value thresholding ($\alpha = 0.05$) on Grafana, while preventing high-cardinality memory leaks on Prometheus TSDB.

---

## 6. Workspace Artifacts Reference

* **Main Interview Prep Roadmap:** [turo-mlops-prep.md](file:///home/laiduy98/projects/roamflow/devops/docs/interview-prep/turo-mlops-prep.md)
* **Model Serving Application Code:** [app.py](file:///home/laiduy98/projects/roamflow/model-serving/src/model_serving/app.py)
* **Serving Unit Tests:** [test_app.py](file:///home/laiduy98/projects/roamflow/model-serving/tests/test_app.py)
* **Serving Helm Values:** [values.yaml](file:///home/laiduy98/projects/roamflow/devops/apps/model-serving/values.yaml)
* **ServiceMonitor Template:** [servicemonitor.yaml](file:///home/laiduy98/projects/roamflow/devops/apps/model-serving/templates/servicemonitor.yaml)
* **Grafana Dashboard ConfigMap:** [dashboard-configmap.yaml](file:///home/laiduy98/projects/roamflow/devops/apps/model-serving/templates/dashboard-configmap.yaml)
* **Dagster ML Pipelines Assets:** [iris.py](file:///home/laiduy98/projects/roamflow/ml-pipelines/src/ml_pipelines/assets/iris.py)
* **Live Grafana Dashboard:** [https://grafana.duylai.duckdns.org/d/ml-model-serving-iris](https://grafana.duylai.duckdns.org/d/ml-model-serving-iris)
* **Live Serving Endpoint:** [https://serving.duylai.duckdns.org/predict](https://serving.duylai.duckdns.org/predict)
