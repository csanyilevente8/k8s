# kubecourse — GKE Environment & CI/CD

Infrastructure and Kubernetes manifests for a small, realistic three-tier
application running on **Google Kubernetes Engine (GKE Standard)**. This repo is
the central home for cluster/shared manifests; the application source lives in
two separate repositories.

This is a hands-on **learning project**: prefer explicit, understandable
resources over abstractions, and deploy manually before automating.

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
| Node pools | `default-pool` (1× e2-micro), `medium-pool` (2× e2-medium) |
| GCP project | `project-f0ad4dfa-b194-4dc6-963` |

The `e2-micro` is memory-constrained; application pods run on `medium-pool`.
Do **not** shrink capacity until real workload resource usage is measured.

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
  --from-literal=POSTGRES_USER=todo \
  --from-literal=POSTGRES_PASSWORD=<password> \
  --from-literal=POSTGRES_DB=todo
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
| 10. Helm packaging | ⏭ next |
| 11. Monitoring (Prometheus/Grafana) | later |
| 12. Jenkins (separate learning phase) | later |

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

## 12. Phase 10 — Helm (later)

After manual manifests + GitHub Actions are understood, convert `todo/` into a
Helm chart so deployment is parameterized (image tags, replicas, resources,
host) and driven by CI.

Target chart shape:

```
charts/todo/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── namespace.yaml
    ├── postgres-*.yaml
    ├── backend-*.yaml
    ├── frontend-*.yaml
    └── ingress.yaml
```

Key values to expose: `image.backend.tag`, `image.frontend.tag`,
`ingress.host`, resource requests/limits, `replicas`. CI then runs
`helm upgrade --install todo charts/todo --set image.backend.tag=<sha> ...`.

---

## 13. Phase 11 — Monitoring (later)

Add Prometheus + Grafana (or GKE Managed Prometheus, which is partly present in
the cluster already). Learning topics: scraping pod/node metrics, Spring Boot
Actuator/Micrometer metrics, dashboards, alerts. Factor its resource footprint
into capacity planning — another reason not to shrink the cluster prematurely.

Spring Boot already exposes `/actuator/health`; enabling
`/actuator/prometheus` (Micrometer) is the natural first step for app metrics.

---

## 14. Phase 12 — Jenkins (later, separate)

Introduce Jenkins only after GitHub Actions CD is working, purely as a learning
exercise (Jenkinsfile, agents, credentials, Kubernetes integration). Do not run
two CD systems against this environment simultaneously.

---

## 15. Capacity plan (revisit after real usage)

Measure actual usage now that the app runs:

```bash
kubectl top nodes
kubectl top pods -n todo
```

- The `e2-micro` (`default-pool`) is memory-constrained and holds mostly system
  DaemonSets. App pods run on `medium-pool`.
- Likely future target: `medium-pool` with autoscaling `min: 1, max: 2`
  (`e2-medium`), and possibly remove `default-pool` — but only after confirming
  all GKE-managed/system workloads fit on the remaining pool.
- Remove nodes via `gcloud container clusters resize` / node-pool operations,
  never `kubectl delete node`. Do not manually resize while autoscaling is
  configured to manage the same pool.

---

## 16. Security notes

- No secrets committed (DB credentials, TLS keys, cloud credentials).
- `nginx-demo/tls.key` (a private key) is present from early experimentation and
  should be removed from history in a cleanup pass; keep this repo **private**.
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
5. App repos are on `main`; each has CI (test+build) **and** CD
   (build/push/deploy via WIF) — a push to `main` that passes CI automatically
   rolls the corresponding GKE deployment.
6. The node service account has `artifactregistry.reader`; the
   `github-deployer` SA + `github-pool`/`github-provider` WIF setup exist.
7. `todo-ip` global static IP is reserved and DNS points to it via GoDaddy.

Next task: **Phase 10** (package `todo/` as a Helm chart; make image tags,
host, replicas, and resources chart values; have CD run
`helm upgrade --install` instead of `kubectl set image`). Then Phase 11
(monitoring) and Phase 12 (Jenkins). Do manual verification before automating;
provide commands for the user to run rather than executing cluster changes
directly.

