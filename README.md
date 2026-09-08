# kubecourse — GKE Environment & CI/CD

Infrastructure and Kubernetes manifests for a small, realistic three-tier
application running on **Google Kubernetes Engine (GKE Standard)**. This repo is
the central home for cluster/shared manifests; the application source lives in
two separate repositories.

This is a hands-on **learning project**: prefer explicit, understandable
resources over abstractions, and deploy manually before automating.

> Setting up on a new/different Mac? See **[SETUP-NEW-MACHINE.md](SETUP-NEW-MACHINE.md)**
> for installing the tooling, authenticating gcloud/kubectl, and the Apple
> Silicon build caveat.

---

## 1. What this project is

A three-tier app on GKE:

- **Angular** frontend (static, served by nginx)
- **Spring Boot** backend (REST API)
- **PostgreSQL** database (in-cluster, for learning StatefulSets/PVCs)
- **HTTPS** via GKE Ingress
- **TLS** via cert-manager + Let's Encrypt
- **CI/CD** via GitHub Actions (Jenkins intentionally postponed)
- **Helm** and **monitoring** planned later

Live URL: **https://todo.leventeprojects.xyz**

```
                 Internet
                    |
              GKE Ingress (HTTPS, Let's Encrypt TLS)
                    |
        /api  →  backend Service (Spring Boot :8080)
        /     →  frontend Service (nginx :80)
                    |
              backend → PostgreSQL (StatefulSet + PVC)
```

---

## 2. Repository layout

Three repositories, deliberately separate:

| Repo | Purpose |
|------|---------|
| `kubecourse` (this repo) | Cluster/shared manifests: namespace, PostgreSQL, Ingress, plus the `nginx-demo` reference. |
| `backend-project` | Spring Boot source + Dockerfile. (`github.com/csanyilevente8/backend-project`) |
| `frontend-project` | Angular source + Dockerfile. (`github.com/csanyilevente8/frontend-project`) |

> Note: the original spec used conceptual names `springboot-backend` /
> `angular-frontend` and put **all** `k8s/` manifests inside each app repo. In
> practice the shared resources (namespace, PostgreSQL, the cross-app Ingress)
> have no natural home in a single app repo, so for this learning phase **all
> manifests live here** in `kubecourse/todo/`. App-owned manifests can be split
> back into the app repos later when per-repo CD is set up.

```
kubecourse/
├── nginx-demo/     # original proven HTTPS reference (do not disturb)
└── todo/           # the real application manifests
    ├── namespace.yaml
    ├── postgres-secret.yaml        # TEMPLATE ONLY (fake values); real secret created via CLI
    ├── postgres-pvc.yaml
    ├── postgres-statefulset.yaml
    ├── postgres-service.yaml       # headless
    ├── backend-config.yaml         # ConfigMap
    ├── backend-deployment.yaml
    ├── backend-service.yaml        # ClusterIP
    ├── frontend-deployment.yaml
    ├── frontend-service.yaml       # ClusterIP
    └── ingress.yaml
```

---

## 3. Cluster

| Item | Value |
|------|-------|
| Cluster | `kubecourse` (GKE Standard) |
| Zone | `europe-central2-a` |
| Node pool | `medium-pool` (e2-medium, autoscaling min 2 / max 3) |
| GCP project | `project-f0ad4dfa-b194-4dc6-963` |

Single node pool: `medium-pool` (e2-medium) with cluster autoscaling (min 2,
max 3). The old `default-pool` (1× e2-micro) was removed during env cleanup —
it was over-committed and held only system DaemonSets. At rest the two nodes sit
~48–54% memory; a 3rd scales up under load (e.g. future in-cluster workloads).

---

## 4. Container images

Google **Artifact Registry**:

```
europe-central2-docker.pkg.dev/project-f0ad4dfa-b194-4dc6-963/kubecourse/backend:<GIT_SHA>
europe-central2-docker.pkg.dev/project-f0ad4dfa-b194-4dc6-963/kubecourse/frontend:<GIT_SHA>
```

- Images are tagged with the **git commit SHA** (immutable), not `latest`.
- Images **must be built for `linux/amd64`** — GKE nodes are amd64. Building on
  an Apple Silicon Mac produces arm64 by default, which fails on the node with
  `no match for platform in manifest`. Use
  `docker buildx build --platform linux/amd64 ... --push`.

---

## 5. TLS / cert-manager

Reuses the proven pattern from `nginx-demo`:

- ClusterIssuer `letsencrypt-prod` (already `Ready`).
- The Ingress carries `cert-manager.io/cluster-issuer: letsencrypt-prod` and
  `acme.cert-manager.io/http01-edit-in-place: "true"` (solve the HTTP-01
  challenge in the existing GKE Ingress/LB rather than a separate solver LB).

---

## 6. Manual deployment (current phase)

Prerequisites (one-time):

1. **Artifact Registry** repo `kubecourse` created; images built for
   `linux/amd64` and pushed.
2. **Node service account** can pull from Artifact Registry:
   ```bash
   gcloud projects add-iam-policy-binding project-f0ad4dfa-b194-4dc6-963 \
     --member="serviceAccount:860228474942-compute@developer.gserviceaccount.com" \
     --role="roles/artifactregistry.reader"
   ```
3. **Global static IP** reserved and DNS pointed at it:
   ```bash
   gcloud compute addresses create todo-ip --global \
     --project=project-f0ad4dfa-b194-4dc6-963
   ```
   GoDaddy A record: `todo.leventeprojects.xyz → <that IP>`.

Create the database Secret out-of-band (never committed):

```bash
kubectl apply -f todo/namespace.yaml
kubectl create secret generic postgres-secret \
  --namespace todo \
  --from-literal=POSTGRES_USER=<db-user> \
  --from-literal=POSTGRES_PASSWORD=<db-password> \
  --from-literal=POSTGRES_DB=<db-name>
```

Apply the rest in dependency order:

```bash
kubectl apply -f todo/postgres-pvc.yaml
kubectl apply -f todo/postgres-service.yaml
kubectl apply -f todo/postgres-statefulset.yaml
kubectl apply -f todo/backend-config.yaml
kubectl apply -f todo/backend-deployment.yaml
kubectl apply -f todo/backend-service.yaml
kubectl apply -f todo/frontend-deployment.yaml
kubectl apply -f todo/frontend-service.yaml
kubectl apply -f todo/ingress.yaml
```

> **Image tag caveat (while CD is active).** The `image:` tags in
> `backend-deployment.yaml` / `frontend-deployment.yaml` are bootstrap values
> only. The CD workflows deploy newer images via `kubectl set image`, so the
> live cluster runs a newer SHA than these files show. **Do not `kubectl apply`
> the deployment files to change images** — it would roll the workload *back* to
> the stale tag. These files are still safe to re-apply for non-image changes
> (replicas, env, probes), but be aware they will reset the image. This drift is
> removed in Phase 10 (Helm). Check the running image with:
> ```bash
> kubectl get deployment backend -n todo \
>   -o jsonpath='{.spec.template.spec.containers[0].image}'
> ```

Verify:

```bash
kubectl get pods,svc,ingress -n todo
kubectl get pvc -n todo                 # postgres-pvc Bound
kubectl get certificate -n todo         # Ready=True (a few minutes)
# backend health, from the LB backend annotation:
kubectl get ingress todo -n todo \
  -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/backends}'
```

---

## 7. Gotchas learned (corrections to the original spec)

These caused real failures during the first deploy and are corrected in the
manifests here:

1. **Branch is `main`, not `master`.** The original spec referenced `master`;
   both app repos and CI use `main`.

2. **Ingress class must use the annotation form on this cluster.**
   `spec.ingressClassName: gce` did **not** work because there is no
   `IngressClass` object named `gce`; the GKE controller never claimed the
   Ingress and no load balancer was provisioned. Use the annotation instead
   (matching `nginx-demo`):
   ```yaml
   metadata:
     annotations:
       kubernetes.io/ingress.class: gce
   ```

3. **Images must be `linux/amd64`** (see section 4). arm64 images built on
   Apple Silicon fail to pull on the amd64 nodes.

4. **Node SA needs `artifactregistry.reader`** or image pulls fail with
   `403 Forbidden` (see section 6).

5. **Resource requests must fit the cluster.** The backend originally requested
   `250m` CPU / `512Mi`, which could not be scheduled given existing load; it
   was lowered to `150m` / `448Mi` (limits unchanged). Right-size after
   measuring with `kubectl top`.

6. **PostgreSQL `PGDATA` subdirectory.** The StatefulSet sets
   `PGDATA=/var/lib/postgresql/data/pgdata` so Postgres initializes into an
   empty subdir instead of the disk mount root (avoids `lost+found` init
   failures on a fresh persistent disk).

7. **Secrets are not committed.** `postgres-secret.yaml` is a template with fake
   `<changeme>` values; the real Secret is created via `kubectl create secret`.

---

## 8. Ingress path routing note

In an Ingress rule, the field `backend:` is Kubernetes terminology for "the
route destination" — it is **not** the Spring Boot backend. Both path rules use
the `backend:` keyword; one points at the `backend` Service (`/api`), the other
at the `frontend` Service (`/`).

---

## 9. Roadmap

| Phase | Status |
|-------|--------|
| 1. Repos + apps | ✅ done |
| 2. Containerization (Dockerfiles, local run) | ✅ done |
| 3. Kubernetes manifests | ✅ done |
| 4. Manual deploy to GKE + HTTPS | ✅ done |
| 7. Artifact Registry | ✅ done |
| 8. Workload Identity Federation (GitHub → GCP, no long-lived keys) | ✅ done |
| 9. GitHub Actions: build + push + deploy on merge to `main` | ✅ done |
| 10. Helm packaging + Helm-based CD (Option B, OCI) | ✅ done |
| 11. Monitoring — metrics + logs + alerts (managed stack) | ✅ done |
| 12. Jenkins (local, learning exercise) | ⏸ in progress (paused) |
| 13. Terraform (Infrastructure as Code) | later |
| 14. Event-driven with Kafka (KRaft) — 4 use cases | 🔄 in progress (UC1 ✅) |

The remaining phases are detailed below with concrete steps so the work can be
resumed in a fresh session. All `gcloud`/`kubectl`/`docker` commands are run by
the user; assistants should provide commands and interpret output, not execute
cluster changes.

---

## 10. Phase 8 — Workload Identity Federation (done)

Set up so GitHub Actions authenticates to Google Cloud using short-lived OIDC
tokens instead of a long-lived service-account JSON key.

What exists now:

- Service account `github-deployer@project-f0ad4dfa-b194-4dc6-963.iam.gserviceaccount.com`
  with `roles/artifactregistry.writer` and `roles/container.developer`.
- Workload Identity pool `github-pool` + OIDC provider `github-provider`
  (issuer `https://token.actions.githubusercontent.com`, restricted to
  repository owner `csanyilevente8`).
- Provider resource name (used by the workflows):
  `projects/860228474942/locations/global/workloadIdentityPools/github-pool/providers/github-provider`
- Both repos (`backend-project`, `frontend-project`) bound as
  `roles/iam.workloadIdentityUser` on the deployer SA.

The `gcloud` commands used to create the above are kept below for reference.

Concept:

```
GitHub Actions job
  → OIDC token
  → Google Workload Identity Federation (pool + provider)
  → impersonate a GCP service account
  → Artifact Registry (push) + GKE (deploy)
```

Values for this project:

- Project: `project-f0ad4dfa-b194-4dc6-963`
- Project number: `860228474942`
- Repos to trust: `csanyilevente8/backend-project`, `csanyilevente8/frontend-project`

### 8.1 Create a deployer service account

```bash
gcloud iam service-accounts create github-deployer \
  --display-name="GitHub Actions deployer" \
  --project=project-f0ad4dfa-b194-4dc6-963
```

Grant it the minimum roles (push images + deploy to GKE):

```bash
SA=github-deployer@project-f0ad4dfa-b194-4dc6-963.iam.gserviceaccount.com

# push to Artifact Registry
gcloud projects add-iam-policy-binding project-f0ad4dfa-b194-4dc6-963 \
  --member="serviceAccount:$SA" --role="roles/artifactregistry.writer"

# deploy to GKE (get credentials + update workloads)
gcloud projects add-iam-policy-binding project-f0ad4dfa-b194-4dc6-963 \
  --member="serviceAccount:$SA" --role="roles/container.developer"
```

### 8.2 Create the Workload Identity pool + provider

```bash
gcloud iam workload-identity-pools create github-pool \
  --location=global \
  --display-name="GitHub Actions pool" \
  --project=project-f0ad4dfa-b194-4dc6-963

gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --display-name="GitHub OIDC" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository_owner=='csanyilevente8'" \
  --project=project-f0ad4dfa-b194-4dc6-963
```

### 8.3 Allow each repo to impersonate the service account

```bash
PNUM=860228474942
POOL="projects/$PNUM/locations/global/workloadIdentityPools/github-pool"

for REPO in backend-project frontend-project; do
  gcloud iam service-accounts add-iam-policy-binding \
    github-deployer@project-f0ad4dfa-b194-4dc6-963.iam.gserviceaccount.com \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/$POOL/attribute.repository/csanyilevente8/$REPO" \
    --project=project-f0ad4dfa-b194-4dc6-963
done
```

### 8.4 Record the provider resource name (needed by the workflows)

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --location=global --workload-identity-pool=github-pool \
  --project=project-f0ad4dfa-b194-4dc6-963 \
  --format="value(name)"
# projects/860228474942/locations/global/workloadIdentityPools/github-pool/providers/github-provider
```

Keep that string; it goes into the workflow as `workload_identity_provider`.

---

## 11. Phase 9 — GitHub Actions build + push + deploy (done)

Each app repo has a `*-cd.yml` workflow that runs **after** its CI succeeds on
`main` (via `workflow_run`, so failing tests never deploy). The CD job:

1. authenticates to GCP via WIF (`google-github-actions/auth@v2`, no keys);
2. builds a `linux/amd64` image tagged with the commit SHA and pushes it to
   Artifact Registry;
3. gets GKE credentials and runs `kubectl set image` + `rollout status`
   (Option A — direct image update, zero-downtime rolling update).

Files:
- `backend-project/.github/workflows/backend-cd.yml`
- `frontend-project/.github/workflows/frontend-cd.yml`

Verified: pushing a change to `main` builds the new image, pushes it, and
performs a rolling update (old pod keeps serving until the new pod passes its
readiness probe). Confirm the live image with:

```bash
kubectl get deployment backend -n todo \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Known tradeoff (Option A): the live image tag can drift from the SHA written in
`todo/*-deployment.yaml` here, since CD updates the cluster directly rather than
this repo. This is removed when Helm (Phase 10) makes the tag a chart value set
by CI.

Notes:
- CD does not run on pull requests, only on pushes to `main`.
- `workflow_run` workflows only trigger once the workflow file is on `main`, so
  the first push of a CD workflow does not deploy; the next push does.
- Any push to `main` redeploys that repo's image even for docs-only changes
  (functionally identical image, new SHA). Add path filters later if desired.

### Reference: the gcloud setup used in Phase 8

```yaml
permissions:
  contents: read
  id-token: write

env:
  PROJECT: project-f0ad4dfa-b194-4dc6-963
  REGION: europe-central2
  REPO: kubecourse
  IMAGE: backend
  CLUSTER: kubecourse
  ZONE: europe-central2-a

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/860228474942/locations/global/workloadIdentityPools/github-pool/providers/github-provider
          service_account: github-deployer@project-f0ad4dfa-b194-4dc6-963.iam.gserviceaccount.com

      - uses: google-github-actions/setup-gcloud@v2

      - run: gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

      - name: Build and push (amd64)
        run: |
          IMG=${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/${IMAGE}:${GITHUB_SHA::7}
          docker build --platform linux/amd64 -t "$IMG" .
          docker push "$IMG"
          echo "IMG=$IMG" >> "$GITHUB_ENV"

      - uses: google-github-actions/get-gke-credentials@v2
        with:
          cluster_name: ${{ env.CLUSTER }}
          location: ${{ env.ZONE }}

      - name: Deploy
        run: |
          kubectl set image deployment/backend backend="$IMG" -n todo
          kubectl rollout status deployment/backend -n todo --timeout=180s
```

Notes / decisions:

- GitHub runners are amd64, so a plain `docker build` produces amd64 — the
  Apple-Silicon arch problem does not occur in CI. `--platform linux/amd64` is
  kept as an explicit guard.
- Manifests currently pin a specific SHA tag. Two options for CD:
  (a) `kubectl set image` to the new tag (shown above), simplest; or
  (b) keep manifests in this repo authoritative and update the tag here
      (GitOps). Start with (a); revisit when Helm/GitOps is introduced.
- The `kubectl set image` approach means the running image can drift from the
  tag written in `todo/backend-deployment.yaml`. When adopting Helm (Phase 10),
  the image tag becomes a chart value set by CI, removing the drift.

Verification after a deploy:

```bash
kubectl rollout status deployment/backend -n todo
kubectl get pods -n todo
kubectl get ingress todo -n todo \
  -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/backends}'
```

---

## 12. Phase 10 — Helm packaging + Helm-based CD (done)

The `todo/` manifests were converted into a Helm chart at `charts/todo/`, and
CD now deploys via Helm from an OCI chart in Artifact Registry (Option B).

Chart layout:

```
charts/todo/
├── Chart.yaml          # version = chart version; appVersion = app version
├── values.yaml         # image tags, replicas, resources, ingress host, etc.
└── templates/
    ├── postgres-pvc.yaml / postgres-statefulset.yaml / postgres-service.yaml
    ├── backend-config.yaml / backend-deployment.yaml / backend-service.yaml
    ├── frontend-deployment.yaml / frontend-service.yaml
    └── ingress.yaml
```

Deliberately **not** in the chart: the `todo` Namespace (provided by
`--namespace`) and the `postgres-secret` Secret (created via kubectl, never in
git). The chart references the Secret by name but does not create it.

### How deployment works (Option B, floating chart version)

Three pipelines, all authenticating with Workload Identity Federation:

- **Chart pipeline** (`k8s` repo, `chart-cd.yml`) — on changes to
  `charts/todo/**`: `helm package` + `helm push` the chart to
  `oci://europe-central2-docker.pkg.dev/.../kubecourse/charts/todo:<version>`,
  then `helm upgrade` that version with `--reset-then-reuse-values` (rolls out
  the chart change, keeps the currently-running image tags).
- **App pipelines** (`backend-project`, `frontend-project`) — on code merge:
  build+push the image, then
  `helm upgrade todo oci://.../charts/todo --reset-then-reuse-values --set <svc>.image.tag=<sha>`
  with **no `--version`** (floats to the latest published chart). Each app
  overrides only its own image tag; the other service's tag is preserved.

Source of truth for the running image tags is **Helm's release state in the
cluster** (not `values.yaml`, whose tags are only bootstrap defaults). Inspect
with `helm get values todo -n todo`.

### Registry auth in CI (gotcha)

Do **not** use `gcloud auth print-access-token | helm registry login` — under
WIF impersonation it fails with `iam.serviceAccounts.getAccessToken denied`.
Instead have the auth action mint the token and pipe it in:

```yaml
- uses: google-github-actions/auth@v2
  id: auth
  with:
    workload_identity_provider: <provider>
    service_account: <deployer-sa>
    token_format: access_token
- run: |
    echo "${{ steps.auth.outputs.access_token }}" \
      | helm registry login europe-central2-docker.pkg.dev \
          --username oauth2accesstoken --password-stdin
```

### Repo-name note

This repository's local directory is `kubecourse`, but the **GitHub repo is
`csanyilevente8/k8s`**. Workload Identity Federation bindings use the *GitHub
repo name*, so the chart pipeline's WIF binding is for `.../attribute.repository/csanyilevente8/k8s`
(not `kubecourse`). The app repos are bound under their real names
(`backend-project`, `frontend-project`).

### Chart version workflow

Bump `version:` in `Chart.yaml` when the chart changes. Because the chart
pipeline is path-filtered to `charts/todo/**`, editing only the workflow file
does not trigger it — a chart content change (e.g. the version bump) does.

---

## 13. Phase 11 — Monitoring (✅ done)

Done: backend exposes `/actuator/prometheus` (Micrometer); a conditional
`PodMonitoring` (chart 0.2.0) has GKE Managed Prometheus scraping it; metrics
visible in Cloud Monitoring. Structured JSON logging + an `X-Request-Id`
correlation id (MDC) ship to Cloud Logging as parsed `jsonPayload` fields.
Cloud Monitoring alert policies configured.

Minor follow-up: `spring.jpa.show-sql: true` prints raw Hibernate SQL to stdout
outside the JSON format; disable it in the deployed profile for fully uniform
structured logs.

### Capacity finding (drives the approach)

`kubectl top nodes` shows the cluster is tight, and — importantly — managed
monitoring is **already running**:

- `medium-pool` nodes: ~48–54% memory used (~1.4Gi free each). (At the time,
  a now-removed `default-pool` e2-micro was over-committed at ~108%.)
- The app itself is tiny (backend ~242Mi, frontend ~4Mi, postgres ~40Mi).
- **Already present:** `gmp-system/collector-*` = **Google Managed Prometheus**;
  `fluentbit-gke-*` = logs already shipped to **Cloud Logging**;
  `kube-state-metrics` running.

**Decision: do NOT self-host Prometheus/Grafana/Loki.** There isn't comfortable
headroom, and it would duplicate what GKE already runs. Use the managed stack
(GMP + Cloud Logging). A self-hosted stack would require adding a node first —
not worth it here.

### A. Metrics (use the existing Managed Prometheus)

1. Backend app change: add `micrometer-registry-prometheus` to `pom.xml` and add
   `prometheus` to `management.endpoints.web.exposure.include` so
   `/actuator/prometheus` is exposed. Deploy via the normal Helm CD.
2. Apply a `PodMonitoring` (gmp) custom resource in the `todo` namespace so the
   existing GMP collectors scrape the backend's `/actuator/prometheus`.
3. View metrics in **Cloud Monitoring** (Metrics Explorer / dashboards). No
   Grafana deploy required. (Optional later: a lightweight Grafana, ~128Mi,
   pointed at the managed backend for custom dashboards.)

Micrometer auto-provides JVM/GC, HTTP request rate+latency, Hikari DB pool, and
Tomcat metrics with no custom code.

### B. Logs (use the existing Cloud Logging)

Logs are already collected by `fluentbit-gke`. Tasks are about *using* and
*improving* them, not deploying infrastructure:

1. Query existing logs — Logs Explorer or:
   ```bash
   gcloud logging read \
     'resource.type="k8s_container" resource.labels.namespace_name="todo"' \
     --limit=50 --project=project-f0ad4dfa-b194-4dc6-963
   ```
2. Backend app change: switch Spring Boot to **structured JSON logging** so
   fields are queryable, and add a **request/correlation id** per HTTP request.

`kubectl logs` remains the quick live-debug tool:
```bash
kubectl logs deploy/backend -n todo -f
kubectl logs <pod> -n todo --previous   # crashed container
```

### C. Alerts

Define a few **Cloud Monitoring** alerting policies (no extra infra): backend
pod down / not ready, high JVM memory or restart loops, HTTP 5xx spike, postgres
not running / PVC near full.

### Suggested order

1. Add Micrometer `/actuator/prometheus` to the backend (small change via CD).
2. Apply `PodMonitoring` so GMP scrapes it; view in Cloud Monitoring.
3. Explore Cloud Logging; then add structured JSON logging + correlation id.
4. A couple of Cloud Monitoring alerts.

Near-zero added cluster load — only two small backend changes plus managed-stack
configuration.

### Aside: the e2-micro node (removed)

The old `default-pool` (e2-micro) was over-committed (~108% memory) doing only
system DaemonSets. It has since been **removed** during env cleanup, after
confirming it held no application pods. The cluster now runs a single
`medium-pool` with autoscaling (min 2, max 3). Node pools are removed via
`gcloud container node-pools delete` (never `kubectl delete node`).

---

## 14. Phase 12 — Jenkins (⏸ in progress — paused, resume later)

Learning exercise to compare with GitHub Actions. Rule: do NOT run two CD
systems against the live `todo` namespace at once — Jenkins only builds/pushes
(no deploy), using its own image tag namespace.

### Decisions made

- **Local Docker Jenkins** (not in-cluster — the cluster is too tight for the
  Jenkins controller + agents).
- Pipeline scope: **test → build → push image** to Artifact Registry. **No
  deploy.**
- First target: the **backend** repo.
- GCP auth: a **service-account JSON key** (long-lived) stored as a Jenkins
  credential. This is a deliberate contrast to the WIF used by GitHub Actions;
  acceptable for a local learning setup, scoped to `artifactregistry.writer`.
- Image tag scheme: `backend:jenkins-<BUILD_NUMBER>` so Jenkins images never
  collide with / get deployed by the GitHub Actions CD.

### Done so far

- Local Jenkins setup lives in `~/eri-proj/jenkins/` (`Dockerfile` +
  `docker-compose.yml`). The image adds Docker CLI, gcloud, and Maven to
  `jenkins/jenkins:lts-jdk17`.
- `docker-compose.yml` mounts the host Docker socket (with `group_add: ["0"]`
  so the non-root jenkins user can use it) and mounts the backend repo
  read-only at `/workspace/backend-project`.
- Verified inside the container: host Docker daemon reachable, repo mounted,
  gcloud + Maven present.
- Jenkins first-run wizard completed (suggested plugins, admin user).
- Jenkins is currently **stopped** (`docker compose down`); the
  `jenkins_jenkins_home` volume is preserved, so restarting resumes the setup.

### To resume

1. Start Jenkins: `cd ~/eri-proj/jenkins && DOCKER_HOST="unix://$HOME/.docker/run/docker.sock" docker compose up -d`; UI at http://localhost:8080.
2. **Stage 2 — GCP auth (not yet done):**
   ```bash
   gcloud iam service-accounts create jenkins-ci \
     --display-name="Local Jenkins CI (Artifact Registry push)" \
     --project=project-f0ad4dfa-b194-4dc6-963
   gcloud projects add-iam-policy-binding project-f0ad4dfa-b194-4dc6-963 \
     --member="serviceAccount:jenkins-ci@project-f0ad4dfa-b194-4dc6-963.iam.gserviceaccount.com" \
     --role="roles/artifactregistry.writer"
   gcloud iam service-accounts keys create ~/jenkins-ci-key.json \
     --iam-account=jenkins-ci@project-f0ad4dfa-b194-4dc6-963.iam.gserviceaccount.com \
     --project=project-f0ad4dfa-b194-4dc6-963
   ```
   Add `~/jenkins-ci-key.json` to Jenkins as a **Secret file** credential with
   ID `gcp-sa-key`, then delete the local key file. NEVER commit the key.
3. **Stage 3 — Jenkinsfile (not yet done):** add a declarative `Jenkinsfile` to
   the backend repo: Test (`mvn test`; Testcontainers works via the mounted
   socket) → Build (`docker build --platform linux/amd64 -t <AR>/backend:jenkins-${BUILD_NUMBER}`)
   → Auth+Push (`gcloud auth activate-service-account --key-file=$GCP_SA_KEY`,
   `gcloud auth configure-docker europe-central2-docker.pkg.dev`, `docker push`).
4. **Stage 4 — Jenkins job:** create a Pipeline job pointing at the Jenkinsfile
   and run it.

Note: the `~/eri-proj/jenkins/` files are local only (workspace root is not a
git repo); they are not committed anywhere.

---

## 14b. Phase 13 — Terraform (Infrastructure as Code, later)

Goal: manage the GCP/GKE infrastructure declaratively with Terraform instead of
the ad-hoc `gcloud` commands used so far, so the environment is reproducible and
reviewable.

Bring these existing, manually-created resources under Terraform:

- GKE cluster `kubecourse` and its node pools
- Artifact Registry repository `kubecourse` (+ its cleanup policy)
- Global static IP `todo-ip`
- IAM: the `github-deployer` service account and its role bindings
- Workload Identity Federation pool/provider (`github-pool` / `github-provider`)
  and the repo `workloadIdentityUser` bindings
- (optionally) the node service account's `artifactregistry.reader` binding

Suggested approach:

- Keep Terraform for **cloud infrastructure** (GCP resources). Keep **in-cluster
  app resources** in Kubernetes manifests / Helm (Phase 10) — do not try to
  manage every Deployment through Terraform. A common split:
  `terraform/` = GCP; `todo/` or Helm chart = Kubernetes workloads.
- Providers: `google` (and `google-beta` where needed).
- **State**: use a remote backend (a GCS bucket) so state is shared and locked,
  not a local file. Create the bucket first (chicken-and-egg: bootstrap it by
  hand or with a tiny local-state config, then migrate).
- **Import, don't recreate**: the cluster, registry, IP, and IAM already exist
  and are in use. Use `terraform import` (or `import` blocks) to bring them into
  state, then `terraform plan` until it shows **no changes** — that proves the
  HCL matches reality before Terraform is allowed to modify anything. Applying
  from scratch would try to recreate live resources.
- Structure: consider modules (`network`, `gke`, `artifact-registry`, `iam-wif`)
  and a `terraform/README.md` documenting `init/plan/apply` and the state bucket.
- CI later: a `terraform plan` on pull requests and `terraform apply` on merge,
  authenticated via the same Workload Identity Federation pattern (a separate SA
  with narrower infra permissions).

Suggested layout:

```
terraform/
├── backend.tf         # remote state (GCS bucket)
├── providers.tf       # google provider, project/region
├── artifact_registry.tf
├── gke.tf
├── network.tf         # static IP, etc.
├── iam_wif.tf         # deployer SA + Workload Identity Federation
├── variables.tf
└── README.md
```

Caution: Terraform manages **real, hard-to-reverse infrastructure**. Always
review `terraform plan` carefully, never auto-approve destroys, and keep the
cluster/registry protected (e.g. `prevent_destroy` lifecycle) so a bad plan
cannot delete the live environment.

---

## 14c. Phase 14 — Event-driven with Kafka (KRaft), later

Goal: learn Kafka by adding **event-driven** features to the Todo app, purely
**additively** — the synchronous CRUD write path (frontend → backend →
Postgres) stays unchanged. Kafka sits alongside it: the backend publishes
events as a fire-and-forget side effect after a successful DB write, and
independent consumers react. If Kafka or a consumer is down, todos still save;
only the async features pause.

```
POST /api/todos ─> write Postgres ─> return 201        (unchanged, synchronous)
                        │
                        └─> publish event to Kafka      (fire-and-forget)
                                     │
                                     ▼
                        consumer group(s) react asynchronously
```

### Broker: Kafka in KRaft mode

Use **Apache Kafka in KRaft mode** (no ZooKeeper — Kafka manages its own
metadata quorum). Single broker for learning, deployed in-cluster as a
StatefulSet + PVC (same pattern as Postgres). KRaft means one component instead
of two, lighter and simpler.

- Namespace: reuse `todo` (or a dedicated `kafka` namespace).
- StatefulSet `kafka` (KRaft combined controller+broker role), headless Service
  for stable DNS, PVC for the log directory.
- Config essentials: `KAFKA_PROCESS_ROLES=broker,controller`, a
  `controller.quorum.voters` entry pointing at itself, `KAFKA_NODE_ID`,
  listeners for broker (9092) and controller (9093), and a formatted storage
  dir (`kafka-storage format` with a cluster UUID) via an init step.
- Capacity note: the cluster is CPU-tight (~940m/node, mostly system pods). A
  single KRaft broker still wants a few hundred Mi + some CPU — check
  `kubectl top nodes` first; it may push the medium-pool to its 3rd
  (autoscaled) node. Set modest requests and a JVM heap cap
  (`KAFKA_HEAP_OPTS=-Xmx512m -Xms512m` or lower).
- Topic(s): a single `todo-events` topic (or per-type topics) with a small
  partition count (1–3 for learning). Created via an init Job or auto-create.

### Producer

The **currently-deployed backend** publishes events after each successful DB
mutation. Since the live backend is Go, use a Go client
(`segmentio/kafka-go` or `franz-go`); if running the Spring backend, use
`spring-kafka`. Publishing is **non-blocking / fire-and-forget** — a failed
publish is logged, never fails the HTTP request. (Implementing it in both
backends is an optional extension of the Go-vs-Spring comparison.)

Event shape (example): `{ "type": "TodoCreated", "id": "...", "title": "...",
"completed": false, "timestamp": "..." }` for types `TodoCreated`,
`TodoUpdated`, `TodoCompleted`, `TodoDeleted`.

### The four use cases (detailed)

#### Use case 1 — Activity log (start here) — ✅ DONE (deployed & verified 2026-09-08)

The foundational case; exercises produce → topic → consume → consumer group.

- **Producer:** backend publishes an event on every create/update/complete/
  delete.
- **Consumer:** a **separate Deployment** (its own image + CI/CD pipeline — good
  microservice practice) in consumer group `activity-logger`, reads
  `todo-events` and appends rows to a new `activity_log` table
  (`id, todo_id, type, detail, created_at`).
- **API/UI:** new `GET /api/activity` (paginated, read-only) on the backend
  reading `activity_log`; a new read-only "Activity" view in the Angular app.
- **Teaches:** producer, topic, consumer, consumer groups, offsets,
  serialization. Zero risk to CRUD.
- **Verify:** create/complete/delete a todo → rows appear in `activity_log` and
  in the Activity view.

**As-built (differs from the plan above):**
- The consumer runs **in-process inside each backend**, not as a separate
  Deployment/image. Gated by env (`KAFKA_BROKERS` for Go; `KAFKA_BROKERS` +
  `APP_KAFKA_ENABLED=true` for Spring). Fire-and-forget producer; the sync CRUD
  path is unchanged. (A standalone consumer microservice is a future refinement.)
- Implemented in **both** backends with an identical JSON event contract on
  topic `todo-events`:
  `{ type: TodoCreated|TodoUpdated|TodoCompleted|TodoDeleted, todoId, title,
  completed, timestamp(RFC3339) }`, keyed by `todoId`.
- `GET /api/activity?limit=N` → newest-first list; default 100, cap 500.
- **Helm:** Kafka is a single-node KRaft StatefulSet (`kafka.enabled`, chart
  ≥0.4.0). When enabled, chart 0.5.0+ injects `KAFKA_BROKERS`
  (`kafka-0.kafka.<ns>.svc.cluster.local:9092`) + `APP_KAFKA_ENABLED=true` into
  the backend. Chart 0.5.1 pins default image tags to the deployed SHAs.
- **Live SHAs (2026-09-08):** backend `go-backend:676bc17`, frontend `d81391d`,
  chart `todo-0.5.1`.
- **Gotcha fixed:** the Go consumer (`segmentio/kafka-go`) defaulted a new group
  to the *end* of the topic, so `/api/activity` stayed empty. Fixed with
  `StartOffset: kafka.FirstOffset` (commit `676bc17`). Verified end-to-end:
  events land in `activity_log`, consumer group lag 0, Activity view populates.
- **Ops caveat:** the Artifact Registry keep-2 cleanup policy pruned a tag a
  Deployment still referenced (`be5b10f`), causing an ImagePullBackOff on
  redeploy. Consider keeping more image versions.

**Next: Use case 2 (notifications / fan-out)** — add a `notifier` consumer group
on the same topic to demonstrate independent fan-out + offset replay.

#### Use case 2 — Notifications / fan-out

> **Decision (2026-09-08): UC2 = Option A (in-process consumer).** Add the
> `notifier` consumer group **inside the existing backend process** (like the
> activity consumer), plus a `notifications` table. Goal: demonstrate *fan-out*
> — one event lands in BOTH `activity_log` and `notifications` from two
> independent consumer groups. Minimal new infra (no new Deployment/image).
> Implement on feature branches in both backends + frontend, same workflow as
> UC1. **Resume here for the next build.**

Shows Kafka's real strength: multiple **independent** consumer groups reading
the **same** events without interfering.

- **Consumer:** a second consumer group `notifier` on the same `todo-events`
  topic. On `TodoCreated` (or a future `TodoDueSoon`) it produces a
  notification — for learning, write to a `notifications` table (or just log).
- **API/UI:** optional `GET /api/notifications` + a bell/badge in the frontend
  that polls it.
- **Teaches:** consumer-group fan-out (activity-logger and notifier both consume
  every event, each at its own offset), and that adding consumers doesn't touch
  the producer.
- **Key demo:** stop the notifier, create todos, restart it — it catches up from
  its committed offset (durability/replay).

#### Use case 3 — Metrics / stream aggregation

> **Decision (2026-09-08): UC3 = Option B (standalone service).** Build the
> `stats-aggregator` as its **own Deployment** — separate image, CI/CD, and a
> Helm template gated by `stats.enabled` — NOT in-process. This is where the
> operational microservice lessons live:
> - **Standalone service:** independent deploy/restart/failure isolation.
> - **Partitions:** the multi-pod load-balancing demo (scale to N pods, Kafka
>   splits partitions across them) needs `todo-events` to have **>1 partition**.
>   The current single-broker topic is likely 1 partition — recreate it with
>   e.g. 3 partitions as part of this UC (a partitioning sub-lesson).
> - **Idempotency:** keyed upserts into `todo_stats` so replays/duplicates
>   don't double-count.
> - **Replay:** `kubectl scale deploy/stats-aggregator --replicas=0`, create
>   todos, scale back up → it resumes from its committed offset and catches up.

A streaming-aggregation mindset: derive a materialized view from the event
stream.

- **Consumer:** consumer group `stats-aggregator` maintains rolling aggregates
  (todos created per day, completion rate, active count) in a `todo_stats`
  table, updated as events arrive.
- **API/UI:** `GET /api/stats` + a small dashboard view (counts/rates; charts
  optional).
- **Teaches:** building a read-optimized projection from events (CQRS-lite),
  idempotent updates, handling out-of-order/duplicate events.
- **Note:** make updates idempotent (e.g. keyed upserts) so replays don't
  double-count.

#### Use case 4 — Real-time UI updates (most advanced)

Close the loop to a live-updating frontend.

- **Consumer/bridge:** a consumer group `realtime-bridge` reads `todo-events`
  and pushes them to connected browsers via **WebSocket or SSE** (a new
  endpoint, e.g. `GET /api/stream`).
- **Frontend:** subscribes to the stream and updates the todo list live when
  any client changes data (no manual refresh).
- **Teaches:** the full event-driven loop end to end (DB change → Kafka →
  consumer → push → UI), plus WebSocket/SSE handling and connection lifecycle.
- **Effort:** highest — adds streaming transport on both backend and frontend.
- **Caveat:** with multiple backend/bridge replicas, a client only receives
  events from the replica it's connected to unless the bridge consumes all
  partitions; for single-replica learning this is fine.

### Suggested build order

1. Deploy KRaft Kafka (single broker) via Helm templates; verify with a console
   producer/consumer (`kafka-console-producer`/`-consumer` in an ephemeral pod).
2. Add the producer to the backend (fire-and-forget) + the `todo-events` topic.
3. Use case 1 (activity log): consumer Deployment + `activity_log` +
   `GET /api/activity` + Activity view.
4. Use case 2 (fan-out): add the `notifier` consumer group; demonstrate replay.
5. Use case 3 (stats): `stats-aggregator` + `GET /api/stats` + dashboard.
6. Use case 4 (real-time): SSE/WebSocket bridge + live frontend updates.

### How it fits the existing setup (nothing breaks)

- **Infra:** Kafka is a new StatefulSet+Service+PVC (same pattern as Postgres),
  templated in the Helm chart behind a `kafka.enabled` flag (like
  `monitoring.enabled`), so the chart still works without it.
- **Consumers:** separate Deployments, each with its own image + CI/CD pipeline
  (more microservice practice) — or, to keep it light, goroutines/threads in the
  backend (simpler, less realistic).
- **Frontend:** only new read-only views/streams are added; existing views
  unchanged.
- **CI/CD, Helm, monitoring:** extend naturally (new chart templates, new
  pipelines, Kafka/consumer metrics via the existing GMP if exposed).

### Tradeoffs / gotchas

- **Resources:** even a single KRaft broker is not free on a tight cluster —
  measure and cap the JVM heap; expect possible use of the autoscaled 3rd node.
- **Delivery guarantees:** fire-and-forget can drop an event if the broker is
  unreachable. Acceptable for learning. The **transactional outbox** pattern
  (write event to a DB table in the same transaction, relay to Kafka) is the
  "never lose an event" upgrade — a good later lesson, not the first step.
- **Idempotency:** consumers should tolerate duplicates/replays (Kafka is
  at-least-once by default) — use upserts/keys, especially for use case 3.
- **Schema:** start with JSON for simplicity; a schema registry + Avro/Protobuf
  is a later refinement.

---


## 15. Capacity plan (current state)

Env cleanup is done. Current layout:

- Single node pool **`medium-pool`** (e2-medium), **autoscaling min 2 / max 3**.
- The old `default-pool` (e2-micro) was removed — it held only system DaemonSets
  and was over-committed.
- At rest: ~48–54% memory per node; the 3rd node scales up under load.

Check usage any time:
```bash
kubectl top nodes
kubectl top pods -n todo
```

Future tuning:
- When adding heavier workloads (e.g. in-cluster Jenkins, a second backend),
  the max=3 gives room; raise max if needed.
- If the app footprint shrinks, consider dropping to `min: 1` (e.g. when trying
  a lighter Go backend) so it can scale down to a single node when idle.

Commands used / to use:
```bash
# enable/adjust autoscaling on the pool
gcloud container clusters update kubecourse --zone=europe-central2-a \
  --enable-autoscaling --node-pool=medium-pool --min-nodes=2 --max-nodes=3
# remove a node pool (drains properly; never `kubectl delete node`)
gcloud container node-pools delete <pool> --cluster=kubecourse --zone=europe-central2-a
```
Do not manually resize a pool while autoscaling manages it.

---

## 16. Security notes

- No secrets committed (DB credentials, TLS keys, cloud credentials).
- The real Let's Encrypt certificate/key are never in git — cert-manager stores
  them in the cluster (`*-tls` Secrets). A self-signed `CN=localhost` test
  cert/key that had been committed under `nginx-demo/` was removed; it was a
  throwaway with no production value (the real cert is
  `CN=nginx.leventeprojects.xyz`, managed in-cluster).
- Keep this repo **private**.
- GitHub → GCP auth uses **OIDC + Workload Identity Federation** (short-lived
  credentials), not long-lived service-account JSON keys (Phase 8).

---

## 17. Resume point (for a new session)

Assume when continuing:

1. Cluster `kubecourse` exists (zone `europe-central2-a`, project
   `project-f0ad4dfa-b194-4dc6-963`, project number `860228474942`).
2. The todo app is deployed and live at **https://todo.leventeprojects.xyz**
   (namespace `todo`; all resources from `todo/` applied; TLS issued).
3. Images are in Artifact Registry
   `europe-central2-docker.pkg.dev/project-f0ad4dfa-b194-4dc6-963/kubecourse`
   (`backend`, `frontend`), tagged by commit SHA, built for `linux/amd64`.
4. cert-manager + `letsencrypt-prod` ClusterIssuer work; the `nginx-demo`
   HTTPS reference remains as a known-good example.
5. App repos are on `main`; each has CI (test+build) **and** CD that deploys
   via **Helm** (build/push image, then `helm upgrade` from the latest OCI
   chart, overriding only that service's image tag). The chart lives in the
   `k8s` repo (`charts/todo/`) and is published to Artifact Registry as an OCI
   chart by its own pipeline. The running image tags are stored in Helm's
   release state (`helm get values todo -n todo`), not in `values.yaml`.
6. The node service account has `artifactregistry.reader`; the
   `github-deployer` SA + `github-pool`/`github-provider` WIF setup exist, with
   `workloadIdentityUser` bindings for repos `k8s`, `backend-project`,
   `frontend-project` (note: the infra repo's GitHub name is `k8s`, local dir
   is `kubecourse`).
7. `todo-ip` global static IP is reserved and DNS points to it via GoDaddy.

Next task: **resume Phase 12 (Jenkins)** — it is paused mid-setup. Local Docker
Jenkins is built and configured (`~/eri-proj/jenkins/`, currently stopped, home
volume preserved). Remaining: Stage 2 (create `jenkins-ci` SA + key, add as
Jenkins credential `gcp-sa-key`), Stage 3 (add `Jenkinsfile` to the backend repo
— test/build/push with tag `backend:jenkins-<BUILD_NUMBER>`, no deploy), Stage 4
(create the Pipeline job and run it). See the Phase 12 section for full detail.
Then Phase 13 (Terraform — import existing GCP/GKE infra, do not recreate). Do
manual verification before automating; provide commands for the user to run
rather than executing cluster changes
directly.

