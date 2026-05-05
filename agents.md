# Repository guide for coding agents

Use this file along with `plan.md` (authoritative product/architecture blueprint).

## Boundaries

- **Terraform** (see `infra/aws/`) owns **account/region** resources. Split roots:
  - **`github_deploy`** — GitHub OIDC + IAM roles for Actions (persists across cluster teardown).
  - **`foundation`** — VPC, EKS, addons, IRSA for AWS Load Balancer Controller.
  - **`k8s_platform`** — Helm `aws-load-balancer-controller`, ExternalDNS, etc.
  - **`parked_site`** — S3 + CloudFront “cluster offline” static site (`static/cluster-offline`), optional Route53.
  - **`deploy_orchestrator`** — Source S3 bucket, Lambda, HTTP API (`POST /deploy`, `/swap`, `/teardown`), DynamoDB job status, EKS access for the Lambda; reads **`foundation`** and **`parked_site`** remote state.
- **Argo CD** still reconciles **Git** for the app-of-apps tree under `deploy/gitops/` unless you narrow or pause Applications; **`deploy-aws`** promotes **rendered manifests** from the bundle into the cluster when SSM **`site_mode=cluster`**, which can overlap with Argo—see **`docs/github-actions.md`** and **`plan.md`**.
- See **`docs/github-actions.md`** for secrets, state keys, and workflows.

**GitHub Actions**

- **Push to `main`**: **`ci.yaml`** runs tests; on success **`deploy-aws.yaml`** builds/pushes images, uploads a release bundle to the orchestrator source bucket, applies **`deploy_orchestrator`**, and invokes **`POST /deploy`** (routes to EKS vs parked static using SSM **`/kubernetes-mono-app/site_mode`**). Repository variable **`DEPLOY_ORCHESTRATOR_EKS=false`** turns off EKS integration (static-only; no live cluster).
- **Manual AWS**: **`swap-stack.yaml`**, **`teardown-aws.yaml`**, **`terraform-apply.yaml`**, destroy / soft-destroy / Argo bootstrap & teardown — see **`docs/github-actions.md`**.
- **Secrets** must not be committed in plaintext; patterns in docs and **`plan.md`**.

## Layout (high signal)

| Path | Purpose |
|------|---------|
| `apps/api` | Go HTTP API, Dockerfile, OpenAPI |
| `infra/aws/github_deploy` | Terraform: GitHub OIDC trust + `gha-terraform` / `gha-bootstrap` IAM roles |
| `infra/aws/foundation` | Terraform: VPC, EKS; reads **`github_deploy`** remote state for role ARNs |
| `infra/aws/k8s_platform` | Terraform: Helm `aws-load-balancer-controller`, ExternalDNS |
| `infra/aws/parked_site` | Terraform: S3 + CloudFront + `/status` → `status.html` function |
| `infra/aws/deploy_orchestrator` | Terraform + Lambda: bundle deploy API, source bucket, job table |
| `infra/aws/deploy_orchestrator/lambda` | Python handler (`build.sh` vendors deps into `package/`) |
| `static/cluster-offline` | Static HTML + mock JSON for parked mode (copied into release bundle) |
| `deploy/gitops` | Root `Application` + app-of-apps children |
| `deploy/base/api` | API Deployment/Service/Ingress; Argo **api** app; ALB **certificate discovery** |
| `deploy/base/portal` | Portal Ingress **`k8s.michaelj43.dev`** + **`/status`**; Argo **portal** app |
| `apps/portal` | Go HTTP server for landing links + status page |
| `deploy/overlays/aws-prod` | Optional Kustomize overlay for prod-only patches |
| `deploy/base/postgres` | CloudNativePG `Cluster` + namespace |
| `deploy/base/redis` | Redis Deployment + Service `redis-master` |
| `infra/argocd` | Helm values for **bootstrap** only |
| `tests/component` | `docker-compose` integration |
| `docs/` | Architecture, TLS, GitOps, **`github-actions.md`**, runbooks |

## Conventions

- Go **module**: `github.com/michaelj43/kubernetes-mono-app/apps/api` — if the GitHub org/user changes, update `go.mod` **import paths** and all imports consistently.
- **`docs/post-merge-runbook.md`**: bring-up order; ensure **`github_deploy`** precedes **`foundation`** on greenfield; **`parked_site`** before **`deploy_orchestrator`**.
- **Ingress** targets `api.k8s.michaelj43.dev`; ACM **must** be in the same region as the ALB. Prefer **certificate discovery** so ARNs are not in Git (`docs/aws-domain-tls.md`). **CloudFront** viewer cert must be **us-east-1** — reuse **`TF_ACM_CERTIFICATE_ARN`** when it is already that regional ARN.
- **Postgres**: operator first (`cnpg-operator` app), then `Cluster` CR; API expects Secret `portfolio-db-app` key **`uri`**.
- After the **first** push to **`main`**, use **feature branches** for subsequent work.

## Testing expectations

- Run `go test ./...` under `apps/api` before declaring API work done.
- For end-to-end local validation, prefer `tests/component/docker-compose.yaml`.

## Security

- Avoid exposing Argo CD on a public hostname without strong auth (see `plan.md` security notes).
- Treat **`argocd-teardown`**, **`soft-destroy`**, **`aws-full-destroy`**, **`teardown-aws`**, and cluster-admin kubeconfigs as destructive capability.
