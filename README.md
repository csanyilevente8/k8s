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
| 1. Repos + apps | ✅ |
| 2. Containerization (Dockerfiles, local run) | ✅ |
| 3. Kubernetes manifests | ✅ |
| 4. Manual deploy to GKE + HTTPS | ✅ |
| 7. Artifact Registry | ✅ |
| 8. Workload Identity Federation (GitHub → GCP, no long-lived keys) | ⏭ next |
| 9. GitHub Actions build + push + deploy on merge to `main` | ⏭ next |
| 10. Helm packaging | later |
| 11. Monitoring (Prometheus/Grafana) | later |
| 12. Jenkins (separate learning phase) | later |

---

## 10. Security notes

- No secrets committed (DB credentials, TLS keys, cloud credentials).
- `nginx-demo/tls.key` (a private key) is present from early experimentation and
  should be removed from history in a cleanup pass; keep this repo **private**.
- Future GitHub → GCP auth will use **OIDC + Workload Identity Federation**
  (short-lived credentials), not long-lived service-account JSON keys.
