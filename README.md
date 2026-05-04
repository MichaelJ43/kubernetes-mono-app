# kubernetes-mono-app

[![Build](https://github.com/MichaelJ43/kubernetes-mono-app/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/MichaelJ43/kubernetes-mono-app/actions/workflows/ci.yaml)
[![Static site](https://github.com/MichaelJ43/kubernetes-mono-app/actions/workflows/static-site-deploy.yaml/badge.svg?branch=main)](https://github.com/MichaelJ43/kubernetes-mono-app/actions/workflows/static-site-deploy.yaml)
[![Terraform apply](https://github.com/MichaelJ43/kubernetes-mono-app/actions/workflows/terraform-apply.yaml/badge.svg?branch=main)](https://github.com/MichaelJ43/kubernetes-mono-app/actions/workflows/terraform-apply.yaml)

Portfolio mono-repo: **Go API**, **portal** (`k8s.michaelj43.dev` landing + public **`/status`**), **GitOps (Argo CD)**, **EKS-oriented manifests** (ALB Ingress, CloudNativePG, Redis), and **GitHub Actions** for CI plus Argo bootstrap/teardown.

> **Costs:** EKS control plane, NAT gateways, ALB, and EBS volumes are not free. Tear down or scale down when not demoing.

## Overview

| Area | Path | Notes |
|------|------|--------|
| API | `apps/api` | HTTP `/health`, `/ready`, `/version`, `/items`, `/cache-demo`; goose migrations |
| Portal | `apps/portal` | Static landing at **`k8s.michaelj43.dev`** + **`/status`** (Argo app names / health / sync); GHCR image tagged **`latest`** plus the **merge commit SHA**; **`deploy/base/portal`** Kustomize **`images[].newTag`** is pinned to that SHA in Git after each **`main`** image build |
| GitOps | `deploy/gitops` | App-of-apps + per-stack `Application` CRs |
| Infra (Terraform) | `infra/aws/github_deploy`, `infra/aws/foundation`, `infra/aws/k8s_platform`, `infra/aws/parked_site` | OIDC IAM (persisted), VPC/EKS, Helm AWS LB controller, optional parked S3/CloudFront |
| Manifests | `deploy/base`, `deploy/overlays/aws-prod` | Kustomize; TLS via ALB **certificate discovery** (no ACM ARN in Git) |
| Argo install | `infra/argocd/values.yaml` | Used only by bootstrap (Actions or Helm CLI) |
| CI | `.github/workflows/ci.yaml` | `go test` (API + portal) on push/PR |
| Images | `.github/workflows/kubernetes-images.yaml` | Manual: GHCR build + Kustomize pin (+ optional rollout) |
| Static parked site | `.github/workflows/static-site-deploy.yaml`, `static/cluster-offline/` | Default on push to `main` when static/terraform paths change |
| Runbooks | `docs/runbooks` | Bootstrap & teardown |

Full design: **`plan.md`**.

```mermaid
flowchart LR
  GH[GitHub repo] --> CI[Actions CI]
  CI --> GHCR[GHCR image]
  GH --> Argo[Argo CD]
  Argo --> EKS[EKS workloads]
  GHCR --> EKS
```

## Replace placeholders

1. **`repoURL` in `deploy/gitops/**/*.yaml`** — defaults to `https://github.com/michaelj43/kubernetes-mono-app.git`.
2. **Container images** — Run **Kubernetes images & deploy pin** (`kubernetes-images.yaml`). It pushes `ghcr.io/<lowercase-github-owner>/kubernetes-mono-app/{api,portal}:<sha>` and `:latest`, then **`pin-images`** updates **`deploy/base/*/kustomization.yaml`** so **`images[].newTag`** is that **`<sha>`**.
3. **Ingress hostname / TLS** — `deploy/base/api/ingress.yaml` (`api.k8s…`) and `deploy/base/portal/ingress.yaml` (**apex `k8s.michaelj43.dev`**) set `spec.tls.hosts` so the **AWS Load Balancer Controller** can **discover** **ACM** (include **`k8s…`** + **`*.k8s…`** on the cert)—**no certificate ARN in Git**. See [`docs/aws-domain-tls.md`](docs/aws-domain-tls.md).

## First full deploy (AWS + Argo)

After infra code is on `main`, follow **[`docs/post-merge-runbook.md`](docs/post-merge-runbook.md)** in order (Terraform → ACM / DNS → image on GHCR → Argo bootstrap → Route 53 alias).

## Quick start (local)

```bash
cd apps/api && go test ./...
cd ../../tests/component && docker compose -f docker-compose.yaml up --build
```

## Docs

- [`docs/post-merge-runbook.md`](docs/post-merge-runbook.md) — **ordered bring-up** after merge
- [`docs/github-actions.md`](docs/github-actions.md) — **Secrets** for Terraform + Argo workflows
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/aws-domain-tls.md`](docs/aws-domain-tls.md)
- [`docs/gitops.md`](docs/gitops.md)
- [`docs/testing.md`](docs/testing.md)

## License

Private / personal portfolio — add a license if you open-source the repo.
