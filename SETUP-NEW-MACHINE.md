# Continuing on a new machine (macOS, Apple Silicon / M1)

How to set up a fresh Mac (e.g. an M1 Air) to keep working on this project:
the GKE cluster, the app repos, and the local dev/build tooling. Written for
**Apple Silicon (arm64)** — note the build caveat in section 7.

Nothing here creates or destroys cloud resources; it connects a new machine to
the **existing** cluster and repos.

---

## 0. Key facts about the environment

| Item | Value |
|------|-------|
| GCP project | `project-f0ad4dfa-b194-4dc6-963` |
| GCP account | `csanyil@gmail.com` |
| GKE cluster | `kubecourse` (zone `europe-central2-a`) |
| Artifact Registry | `europe-central2-docker.pkg.dev/project-f0ad4dfa-b194-4dc6-963/kubecourse` |
| kube context | `gke_project-f0ad4dfa-b194-4dc6-963_europe-central2-a_kubecourse` |
| App URL | https://todo.leventeprojects.xyz |

Repos (GitHub, owner `csanyilevente8`):
- `k8s` (this repo — local dir usually `kubecourse`): manifests + Helm chart
- `backend-project`: Spring Boot backend
- `frontend-project`: Angular frontend
- `go-backend-project`: Go backend (current default)

---

## 1. Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
Follow the post-install step it prints to add brew to your PATH (Apple Silicon
installs to `/opt/homebrew`).

## 2. Install the tooling

Versions this project is known-good with (as of 2026-09):

| Tool | Version used | Install |
|------|--------------|---------|
| Google Cloud SDK | 583+ | `brew install --cask google-cloud-sdk` |
| kubectl | 1.34 | `gcloud components install kubectl` (or `brew install kubectl`) |
| Helm | 4.x | `brew install helm` |
| Docker Desktop | 29+ | `brew install --cask docker` (then launch it) |
| Java 17 (Temurin/Corretto) | 17 | `brew install --cask temurin@17` |
| Maven | 3.9 | `brew install maven` |
| Node.js LTS | 24 | `brew install node` (or use `nvm`) |
| Go | 1.25+ | `brew install go` |
| GKE auth plugin | — | `gcloud components install gke-gcloud-auth-plugin` |

```bash
brew install --cask google-cloud-sdk docker temurin@17
brew install helm maven node go
gcloud components install kubectl gke-gcloud-auth-plugin
```

Start Docker Desktop once from Applications so its daemon/socket come up.

## 3. Authenticate gcloud

```bash
gcloud auth login                       # opens a browser; sign in as csanyil@gmail.com
gcloud config set project project-f0ad4dfa-b194-4dc6-963
gcloud auth application-default login   # ADC, used by some tools/libraries
```

Verify:
```bash
gcloud config list
gcloud projects describe project-f0ad4dfa-b194-4dc6-963 --format="value(projectId)"
```

## 4. Connect kubectl to the cluster

```bash
gcloud container clusters get-credentials kubecourse \
  --zone europe-central2-a \
  --project project-f0ad4dfa-b194-4dc6-963
```
This writes the kube context. Verify:
```bash
kubectl config current-context     # gke_..._kubecourse
kubectl get nodes
kubectl get pods -n todo
```
If `kubectl` complains about authentication, ensure the auth plugin is
installed (section 2) — GKE requires `gke-gcloud-auth-plugin`.

## 5. Docker & Helm auth to Artifact Registry

For pushing images / pulling the OCI Helm chart locally:
```bash
gcloud auth configure-docker europe-central2-docker.pkg.dev

# Helm OCI login (token is short-lived, ~1h — re-run when it expires)
gcloud auth print-access-token \
  | helm registry login europe-central2-docker.pkg.dev \
      --username oauth2accesstoken --password-stdin
```

## 6. Clone the repos

```bash
mkdir -p ~/eri-proj && cd ~/eri-proj
git clone git@github.com:csanyilevente8/k8s.git kubecourse
mkdir -p fullstacktodo && cd fullstacktodo
git clone git@github.com:csanyilevente8/backend-project.git
git clone git@github.com:csanyilevente8/frontend-project.git
git clone git@github.com:csanyilevente8/go-backend-project.git
```
(Set up an SSH key with GitHub first, or use HTTPS URLs.)

Note: `fullstacktodo/` is just a local container directory — it is NOT a git
repo. The three app repos and `kubecourse` are independent repos.

## 7. Apple Silicon (arm64) build caveat — IMPORTANT

GKE nodes are **amd64**. Docker on an M1 builds **arm64** by default, which will
fail to run on the nodes with `no match for platform in manifest`.

Always build images for amd64 and push:
```bash
docker buildx build --platform linux/amd64 -t <IMAGE> --push .
```
CI (GitHub Actions) runs on amd64 runners, so the pipelines build correctly
without this flag — this caveat is only for **local** image builds.

## 8. Local development (run the stack without the cluster)

PostgreSQL runs in Docker; the apps run natively. Helper scripts live in the
`fullstacktodo/` workspace root (`start-db.sh`, `stop-db.sh`, `run-backend.sh`,
`run-frontend.sh`). Manually:

```bash
# 1. PostgreSQL
cd ~/eri-proj/fullstacktodo
docker compose up -d            # (docker-compose.yml is here)

# 2a. Go backend (current default)
cd go-backend-project
export DB_PASSWORD=todo
go run ./cmd/server             # http://localhost:8080

# 2b. OR Spring backend
cd ../backend-project
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
export DB_PASSWORD=todo
mvn -s .mvn/settings.xml spring-boot:run

# 3. Frontend
cd ../frontend-project
npm ci
npm start                       # http://localhost:4200
```

Notes:
- `DB_PASSWORD` is **required** by both backends (no default) — export it.
- The Spring build uses `-s .mvn/settings.xml` to bypass a corporate Maven
  mirror and build against Maven Central. On a personal machine without that
  mirror you can usually drop `-s .mvn/settings.xml`.
- Set `JAVA_HOME` to Java 17 for Maven (a newer default JDK may be picked up
  otherwise).

## 9. Working with the cluster / Helm

```bash
# what's deployed
kubectl get pods,svc,ingress -n todo
helm list -n todo
helm get values todo -n todo

# deploy the chart (needs helm registry login from section 5)
helm upgrade todo \
  oci://europe-central2-docker.pkg.dev/project-f0ad4dfa-b194-4dc6-963/kubecourse/charts/todo \
  -n todo --reset-then-reuse-values --wait

# logs / usage
kubectl logs deploy/backend -n todo -f
kubectl top pods -n todo
kubectl top nodes
```

## 10. Testing the live app from a filtered network

Some corporate networks intercept `todo.leventeprojects.xyz` (DNS filtering).
If `curl https://todo.leventeprojects.xyz` returns a block page, test from
inside the cluster instead:
```bash
kubectl run t --rm -i --restart=Never --image=curlimages/curl -n todo -- \
  -s -o /dev/null -w "%{http_code}\n" http://backend:8080/api/todos
```
Or use a non-corporate network / phone hotspot for the public URL.

## 11. Git push note

Pushing may require a signing flag depending on your git config:
```bash
git push --no-signed origin main
```
Do not push directly to app repos' `main` casually — pushes trigger CI/CD which
builds and deploys.

---

## Quick verification checklist on the new machine

- [ ] `gcloud config list` shows the right account + project
- [ ] `kubectl get nodes` lists the medium-pool node(s)
- [ ] `kubectl get pods -n todo` shows backend/frontend/postgres Running
- [ ] `helm list -n todo` shows the `todo` release
- [ ] `docker buildx build --platform linux/amd64 ...` works (Docker running)
- [ ] `go build ./...` works in `go-backend-project`
- [ ] Local stack runs (Postgres in Docker + a backend + frontend)

Where to pick up the course: see this repo's main `README.md` — the roadmap and
"Resume point" section describe the current phase and next steps.
