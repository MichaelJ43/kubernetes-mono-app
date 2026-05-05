# AWS (Terraform)

Stacks share one **S3 backend** (different keys) and one **DynamoDB** lock table.

| Stack | Path | What it creates |
|-------|------|-----------------|
| **github_deploy** | `infra/aws/github_deploy` | GitHub OIDC trust + IAM roles **`…-gha-terraform`** / **`…-gha-bootstrap`** (survives cluster destroy). |
| **foundation** | `infra/aws/foundation` | VPC, EKS, IRSA for AWS LB Controller, EKS access entries for **`github_deploy`** roles (IAM lookup by **`…-gha-*`** name). |
| **k8s_platform** | `infra/aws/k8s_platform` | **Helm**: `aws-load-balancer-controller`; optional **ExternalDNS** when Route53 zone ID is set. |
| **parked_site** | `infra/aws/parked_site` | S3 + CloudFront + optional Route53 for **`static/cluster-offline`** (parked / offline messaging). |
| **deploy_orchestrator** | `infra/aws/deploy_orchestrator` | Source S3 bucket for release bundles, Lambda + HTTP API (**`POST /deploy`**, **`/swap`**, **`/teardown`**), DynamoDB job status. Reads **`parked_site`** remote state always; reads **`foundation`** only when CI passes a non-empty **`foundation_state_key`** (object exists in the state bucket). EKS access for the Lambda is enabled only when **`cluster_name`** from that state matches a live cluster in the account. |

**Argo CD** is installed by **GitHub Actions** (`terraform-apply.yaml`) after **`k8s_platform`** — not by Terraform alone. Application rollouts also run via **`deploy-aws`** when SSM **`site_mode=cluster`** (bundle apply).

## Prerequisites

- AWS account, `aws` CLI for first apply.
- **S3 bucket** + **DynamoDB table** for Terraform state.
- GitHub **Secrets** — [`../docs/github-actions.md`](../docs/github-actions.md).

## First apply (local)

1. **`github_deploy`** first (until those IAM roles exist, **`foundation`** cannot resolve access entry principals):
   - Copy [`examples/backend-github-deploy.hcl.example`](examples/backend-github-deploy.hcl.example) → `backend.hcl` (gitignored).
   - `terraform init -backend-config=backend.hcl` / `apply` from `infra/aws/github_deploy` with `terraform.tfvars` (org, repo, `cluster_name` matching foundation).
2. **`foundation`**: copy [`examples/foundation/terraform.tfvars.example`](examples/foundation/terraform.tfvars.example), including **`state_*`** (and **`github_deploy_state_key`** if your CI still passes it — unused by **`foundation`** for IAM).
3. **`k8s_platform`**: same pattern as before; **`foundation_state_key`** must match **`foundation`** state object key.

Or run **Actions → Terraform apply** once secrets exist (no workflow inputs) — it applies **`github_deploy`** → **`foundation`** → **`k8s_platform`** → Argo CD.

## Destroy order

- **Terraform destroy** / **Full undeploy**: **`k8s_platform`** then **`foundation`** (does not remove **`github_deploy`** or **`parked_site`**).
- **Soft destroy** / **AWS full destroy**: see [`../docs/github-actions.md`](../docs/github-actions.md).

## Cost notes

- Default **`enable_nat_gateway = false`** in **`foundation`** uses public subnets for nodes (no NAT).
- **`parked_site`** uses **CloudFront** + **S3** (small ongoing cost vs EKS).

## Files

- Commit **`.terraform.lock.hcl`** per stack directory.
