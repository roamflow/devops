# Chuẩn bị phỏng vấn Turo – (Senior/Staff) MLOps Engineer

> File theo dõi tiến độ. Cập nhật checkbox và mục "Nhật ký" sau mỗi buổi làm.
> Cách làm: **bạn gõ lệnh, AI hỏi và giải thích từng dòng**. Mỗi bước kết thúc bằng 3 câu trả lời + 1 đoạn STAR bằng tiếng Anh.

- Vị trí: MLOps Engineer, Paris (JD ghi Senior, trang ứng tuyển ghi Staff, lương 70–87k€ nên nhiều khả năng là Senior).
- Ứng tuyển: 2026-09-29. Phỏng vấn bằng **tiếng Anh**.
- Ngày phỏng vấn: `TODO: điền ngày`  | Số ngày còn lại: `TODO`
- Việc cần hỏi recruiter: level thật (Senior hay Staff), quy trình các vòng, có live coding / system design không.

---

## 1. JD yêu cầu gì (rút gọn)
- Ray, MLflow, Airflow, Docker, Kubernetes (stack nêu đích danh).
- Terraform (IaC), Python (Java/Kotlin là điểm cộng).
- Pipeline ML từ feature đến deploy; batch + real-time; feature store, artifact registry.
- Mentor team, cộng tác với Data Science.
- Bài toán nghiệp vụ: Pricing, Risk/Fraud, Search/Recommendation.

> Không đoán quá sâu stack nội bộ (Feast, Triton, Kafka...). Hãy hỏi lại họ thay vì khẳng định.

---

## 2. Hiện trạng lab (tính đến 2026-10-10)

Cluster `roamflow`: k3s v1.34, 2 node ARM64 (2 vCPU / 12GB mỗi node), OCI Always Free.

**Đã có**
- Argo CD (app-of-apps), Sealed Secrets, cert-manager, Traefik, Authentik SSO.
- MLflow 3.15.2 (SQLite + artifact trên local-path PVC), Dagster (webserver + daemon + Postgres).
- Prometheus/Grafana, Loki, Promtail.
- Lịch sử tuning MLflow (OOM, workers, memory) => chất liệu STAR.

**Điểm yếu đã biết**
- Chưa viết Helm template nào (chỉ umbrella chart bọc chart bên thứ ba; template tự viết duy nhất là sealed-secrets).
- MLflow dùng SQLite + local PVC, chỉ 1 replica, `Recreate`.
- Dagster cài venv lúc init trên `python:3.11-slim`, chưa có image build riêng.
- Chưa có: serving, Ray/KubeRay, Terraform, CI/CD cho model, ServiceMonitor/dashboard cho ML.

---

## 3. Lộ trình (làm theo thứ tự này)

Thứ tự ưu tiên nếu thiếu thời gian: **1 → 2 → 6 → 8 → 4 → 3 → 5 → 7**

- [x] **Bước 1 – Helm chart `model-serving`**
  - Tự viết: Deployment, Service, Ingress, HPA, `values.yaml`, `_helpers.tpl`.
  - Học: templating, values, probe, resource, HPA, GitHub Actions ARM64 build.
  - Câu hỏi phỏng vấn: "Design a low-latency serving layer."
- [ ] **Bước 2 – Rollout an toàn + rollback**
  - Rolling update, canary hoặc blue/green, rollback khi metric xấu.
  - Câu hỏi: "How do you ship a new model without dropping requests?"
- [ ] **Bước 3 – Train → Registry → Serve**
  - Dagster train, log vào MLflow, register, serving đọc model từ registry.
  - Câu hỏi: "What happens when someone promotes a model to prod?"
- [ ] **Bước 4 – Ray / KubeRay**
  - Cài KubeRay, chạy Ray cluster nhỏ, submit job. Đặt requests/limits chặt (chỉ 24GB RAM).
  - Có thể thử Ray Serve so với FastAPI.
  - Câu hỏi: "How do you run Ray on K8s? How do you handle OOM / GPU allocation?"
- [ ] **Bước 5 – Terraform**
  - Bọc phần bootstrap (namespace, helm_release, secret) bằng Terraform, có module.
  - Câu hỏi: "How do you structure Terraform?"
- [ ] **Bước 6 – Observability cho ML**
  - ServiceMonitor, dashboard Grafana (latency, throughput, error), một metric drift đơn giản.
  - Câu hỏi: "What do you monitor besides CPU and memory?"
- [ ] **Bước 7 – Nâng MLflow lên Postgres + MinIO**
  - Giải thích trade-off so với SQLite + PVC.
  - Câu hỏi: "Why is SQLite not production ready? What breaks first?"
- [ ] **Bước 8 – Incident / Chaos (viết STAR)**
  - Cố ý gây: OOM, kill pod, rollout lỗi, data xấu. Trace nguyên nhân, sửa, thêm guardrail.
  - Câu hỏi: "Tell me about a production failure."

**Việc bổ sung (nhẹ, làm xen kẽ)**
- [ ] CI/CD: test → build image → push Gitea registry → Argo CD sync.
- [ ] Đóng gói Dagster thành image riêng (thay venv lúc init).
- [ ] Feature store và train-serve skew: chỉ cần giải thích được, có thể thử ví dụ nhỏ.

---

## 4. Checklist ngoài lab
- [ ] Phần tự giới thiệu 1–2 phút bằng tiếng Anh, luyện nói to.
- [ ] 2–3 dự án thật kể bằng STAR, có số liệu.
- [ ] 2 bài system design trên giấy: (a) ML serving cho dynamic pricing, (b) ML platform cho team 10 DS. Khung: requirements → kiến trúc → trade-off → monitoring → cost.
- [ ] Ôn Python (live coding): xử lý dữ liệu, concurrency cơ bản, viết test.
- [ ] Giải thích được vì sao dùng **Dagster thay Airflow**, và khác biệt chính giữa hai cái.
- [ ] Câu hỏi hành vi: cộng tác với DS, bất đồng, mentoring, hybrid 3 ngày/tuần.
- [ ] Danh sách câu hỏi ngược lại cho họ (xem mục 6).

---

## 5. Mẫu kết thúc mỗi bước (điền vào Nhật ký)
1. Vì sao chọn công cụ/cách làm này, không chọn cái khác?
2. Nó hỏng ở đâu khi lên production?
3. Nếu có 100 model thay vì 1, mình đổi gì?
4. STAR bằng tiếng Anh (Situation, Task, Action, Result).

---

## 6. Câu hỏi ngược lại cho Turo
- ML platform đang ở giai đoạn nào (xây mới hay mở rộng)?
- Pain point lớn nhất của team Data Science hiện nay?
- Cloud nào, on-call ra sao?
- Model nào đang ở production, tỷ lệ batch / real-time?
- Hiện đã có feature store chưa?
- Level của vị trí này (Senior hay Staff) và kỳ vọng cụ thể?

---

## 7. Nhật ký tiến độ
> Mỗi lần làm xong, thêm một dòng: ngày – việc đã làm – việc dang dở – điều đã học.

| Ngày | Đã làm | Dang dở / lưu ý | Điều học được |
|---|---|---|---|
| 2026-10-10 | Đọc repo devops, chốt lộ trình, tạo file này | Chưa bắt đầu Bước 1; chưa có ngày phỏng vấn | – |
| 2026-10-10 | Tạo project `model-serving` (uv, FastAPI + MLflow client 3.17.0). Nâng MLflow server 3.15.2 → 3.17.0 (backup SQLite, push, Argo sync, `/health` 200). Cập nhật README | Chưa có code app; backup ở `devops/.secrets/backups/` có thể xoá sau vài ngày | Argo auto-sync + `Recreate` gây downtime ngắn; nên ghim client cùng version server; build image phải `linux/arm64` (máy x86_64, cluster ARM64) |
| 2026-10-10 | Hoàn thành **Bước 1**: FastAPI app, lifespan load model, liveness/readiness/startup probes, GitHub Actions ARM64 build ra ghcr.io, Helm chart tự viết đầy đủ (Deployment, Service, HPA, Ingress, helpers), Argo CD App deployed và Healthy trên k3s ARM64. Chuẩn hóa tag image `v<version>-<short_sha>` (SemVer + immutable SHA: `v0.1.0-5d94572`). | Chưa có rollout an toàn / canary (sang Bước 2) | Khác biệt liveness vs readiness; omission `replicas` khi dùng HPA trong Helm; không giới hạn CPU limit tránh latency throttling; zero-downtime rolling update (maxUnavailable: 0, maxSurge: 1, preStop sleep); tag chuẩn SemVer + Short SHA giúp vừa human-readable vừa traceable 1-1. |
| 2026-10-10 | Thiết lập hoàn chỉnh **Vòng lặp GitOps Push Promotion tự động** phân tách 3 jobs độc lập: `test` (ruff + pytest) ──► `build` (ARM64 Docker buildx + GHCR push, xuất output `tag`) ──► `promote` (dùng Deploy Key scoped SSH, checkout `devops`, bump `image.tag` và commit `[skip ci]`). Argo CD tự nhận diện và rolling update zero-downtime lên pod mới (`v0.1.0-72e22c3`). | – | Tách rời 3 jobs: bảo mật Supply Chain (job build không chạm vào khóa SSH của infra), secret scoping, retry độc lập chỉ job promote mà không cần build lại image Docker, runner tối ưu (`ubuntu-latest` cho git operations, ARM64 cho build/test). |
| 2026-10-10 | **Tái cấu trúc Dagster thành Modular Helm Chart & Debug 500 Internal Server Error** (`devops/apps/dagster`): Tách sạch sẽ Control Plane (Webserver + Daemon + Postgres + Ingress) khỏi Code Location. Loại bỏ hoàn toàn anti-pattern nhúng code python pipeline vào ConfigMap hay cài ML packages trong Control Plane. Fix bug sâu: SQLAlchemy 2.0+ tự nhận `psycopg` (v3) thay vì `psycopg2`, khiến lệnh `NOTIFY run_events, $1;` bị PostgreSQL báo syntax error làm chết connection (`connection is closed` ──► Webserver 500). Fix triệt để bằng `scheme: postgresql+psycopg2`. Nâng tài nguyên an toàn (DB 512Mi, Daemon 1Gi). Webserver trả về HTTP 200 mượt mà trên `https://dagster.duylai.duckdns.org`. | Chuẩn bị repo riêng cho user code location (gRPC server) và pipeline ML. | **Senior/Staff Architecture lesson**: (1) Trong Dagster production, tuyệt đối không chạy pipeline bên trong Webserver/Daemon process. (2) Chú ý khác biệt DBAPI driver giữa psycopg2 vs psycopg3: psycopg3 dùng parameterized query `$1` cho mọi statement, không tương thích với Postgres `NOTIFY channel, payload`. Cần chỉ định tường minh dialect `postgresql+psycopg2`. (3) Không để limits DB/Daemon quá sát tránh OOMKill ngầm. |
| 2026-10-10 | Hoàn thành **Tách & Deploy User Code Location gRPC riêng biệt (`ml-pipelines`)**: Khởi tạo repo `roamflow/ml-pipelines` (Python 3.12, `uv`), viết Software-Defined Assets (`iris_data`, `train_and_register_iris_model`) log MLflow 3.17 & set alias `@Production`. Dockerfile ARM64 native với uv cache mount chạy `dagster api grpc -p 4000`. GitHub Actions test -> build -> promote. Viết Helm chart `apps/ml-pipelines` và Argo CD App `ml-pipelines` deploy vào k3s. Kết nối thành công qua gRPC tới Dagster Webserver (`workspace.yaml`), GraphQL verify đã nhận 2 assets sẵn sàng materialize! | Bước tiếp theo: Kích hoạt materialize asset từ UI hoặc GraphQL để huấn luyện model thật vào MLflow Registry, sau đó switch `model-serving` sang load model từ MLflow qua alias `Production`. | Tách biệt gRPC code server là cốt lõi của Modern Data/ML Platform: Data Engineer/DS toàn quyền update repo của mình, chạy CI/CD riêng và deploy pod code-server mới mà không hề chạm vào hay restart hạ tầng Dagster Webserver/Daemon. |



---

## 8. Ghi chú cho phiên chat sau
- Mở file này đầu mỗi phiên và nhờ AI đọc để biết đang ở bước nào.
- Nguyên tắc: bạn gõ lệnh, AI hướng dẫn, hỏi lại vì sao, giúp debug.
- Khi xong một bước: tick checkbox và thêm dòng vào Nhật ký.
