# Repository guide for coding agents

Use this file along with `plan.md` (authoritative product/architecture blueprint).

## Boundaries

- **Terraform** (see `infra/aws/`) owns **account/region** resources: VPC, EKS, cluster addons, AWS Load Balancer Controller (Helm in `k8s_platform` stack), and **GitHub OIDC** IAM roles. **Argo CD** owns **Kubernetes application** state under `deploy/gitops/`. See `docs/github-actions.md` for GitHub Secrets/Variables.
- **GitHub Actions** owns **CI** (build/test/image, optional EKS rollout after push to **`main`**) and **lifecycle** workflows (Argo bootstrap/teardown)—see `.github/workflows/` and **`docs/github-actions.md`** (**`EKS_CLUSTER_NAME`**).
- **Secrets** must not be committed in plaintext. Examples: copy patterns from docs; use External Secrets, Sealed Secrets, or manual one-time `kubectl` creation as described in `plan.md` §4.4.

## Layout (high signal)

| Path | Purpose |
|------|---------|
| `apps/api` | Go HTTP API, Dockerfile, OpenAPI |
| `infra/aws/foundation` | Terraform: VPC, EKS, addons, GitHub OIDC roles, IRSA for LB controller |
| `infra/aws/k8s_platform` | Terraform: Helm `aws-load-balancer-controller` |
| `deploy/gitops` | Root `Application` + app-of-apps children |
| `deploy/base/api` | API Deployment/Service/Ingress; Argo **api** app syncs this path; ALB **certificate discovery** (no ACM ARN in Git) |
| `deploy/base/portal` | Portal Deployment/Ingress **`k8s.michaelj43.dev`** + **`/status`** (reads Argo `Application` CRs in `argocd`); Argo **portal** app |
| `apps/portal` | Go HTTP server for landing links + status page |
| `deploy/overlays/aws-prod` | Optional Kustomize overlay for prod-only patches (defaults to wrapping `base/api` without ACM annotations) |
| `deploy/base/postgres` | CloudNativePG `Cluster` + namespace |
| `deploy/base/redis` | Redis Deployment + Service `redis-master` (Docker Official image on ECR Public) |
| `infra/argocd` | Helm values for **bootstrap** only |
| `tests/component` | `docker-compose` integration |
| `docs/` | Architecture, TLS, GitOps, testing, runbooks |

## Conventions

- Go **module**: `github.com/michaelj43/kubernetes-mono-app/apps/api` — if the GitHub org/user changes, update `go.mod` **import paths** and all imports consistently.
- **`docs/post-merge-runbook.md`**: ordered bring-up after infra is on `main` (Terraform → TLS → Argo).
- **Ingress** targets `api.k8s.michaelj43.dev`; ACM **must** be in the same region as the ALB. Prefer **certificate discovery** so ARNs are not in Git (`docs/aws-domain-tls.md`).
- **Postgres**: operator first (`cnpg-operator` app), then `Cluster` CR; API expects Secret `portfolio-db-app` key **`uri`** (CloudNativePG application secret). If keys differ in your CNPG version, adjust `deploy/base/api/deployment.yaml` and document.
- After the **first** push to `main`, use **feature branches** for subsequent work; only the initial bootstrap used `main` as requested by the repo owner.

## Testing expectations

- Run `go test ./...` under `apps/api` before declaring API work done.
- For end-to-end local validation, prefer `tests/component/docker-compose.yaml`.

## Security

- Avoid exposing Argo CD on a public hostname without strong auth (`plan.md` §10).
- Treat `argocd-teardown` and cluster-admin kubeconfigs as destructive capability.
