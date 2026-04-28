# GitHub Actions: secrets and variables

Configure these under **Settings → Secrets and variables → Actions** for the repository.

## Secrets (`Settings → Secrets and variables → Actions → Secrets`)

| Name | Required | Used by |
|------|----------|---------|
| **`AWS_ROLE_ARN_TERRAFORM`** | Yes (after first foundation apply) | `terraform-plan.yaml`, `terraform-apply.yaml`, `terraform-destroy.yaml` — OIDC assume-role for Terraform (`AdministratorAccess` on the role this repo creates). |
| **`AWS_ROLE_ARN_BOOTSTRAP`** | Yes (same as Terraform output `github_actions_bootstrap_role_arn`) | `argocd-bootstrap.yaml`, `argocd-teardown.yaml` — narrower AWS API + EKS cluster admin via **EKS access entry** (install Helm / `kubectl`). |

For a first-time bring-up you can set **both secrets to the ARNs output by Terraform** after your **first local** `terraform apply` (see below). They are **different IAM roles** in this design.

## Variables (`Settings → Secrets and variables → Actions → Variables`)

| Name | Example | Purpose |
|------|---------|---------|
| **`TF_STATE_BUCKET`** | `my-terraform-state-bucket` | S3 bucket for Terraform state (you already have this). |
| **`TF_STATE_REGION`** | `us-east-1` | Region where the **state bucket and DynamoDB table** live (often same as EKS region). |
| **`TF_LOCK_TABLE`** | `my-terraform-locks` | DynamoDB table for state locking. |
| **`TF_FOUNDATION_STATE_KEY`** | `kubernetes-mono-app/foundation/terraform.tfstate` | S3 object key for **foundation** stack (VPC + EKS + IAM + IRSA for LBC). |
| **`TF_K8S_PLATFORM_STATE_KEY`** | `kubernetes-mono-app/k8s-platform/terraform.tfstate` | S3 object key for **k8s_platform** stack (Helm: AWS Load Balancer Controller). |

Optional convenience (not read by workflows today; use in docs / future):

| Name | Example | Notes |
|------|---------|-------|
| **`EKS_CLUSTER_NAME`** | `k8s-mono` | Should match `cluster_name` in `infra/aws/foundation` — document only; bootstrap workflow still asks for cluster name unless you extend the workflow. |

## First-time chicken-and-egg

The **GitHub OIDC IAM roles** (`github_actions_terraform_role_arn` and `github_actions_bootstrap_role_arn`) are **created by the foundation stack**. Until they exist, GitHub Actions cannot assume them.

1. From your laptop (administrator or power-user AWS credentials), configure the S3 backend and run **foundation** only:
   ```bash
   cd infra/aws/foundation
   terraform init -backend-config=../../examples/backend-foundation.hcl  # copy/edit example first
   export TF_VAR_aws_region=us-east-1
   export TF_VAR_github_organization=MichaelJ43
   export TF_VAR_github_repository=kubernetes-mono-app
   terraform apply
   ```
2. Copy **outputs** `github_actions_terraform_role_arn` → **`AWS_ROLE_ARN_TERRAFORM`**, `github_actions_bootstrap_role_arn` → **`AWS_ROLE_ARN_BOOTSTRAP`**.
3. Set the **Variables** table above to match your bucket/table/keys.
4. Run **Terraform apply** workflow (`workflow_dispatch`, confirm `APPLY`) to align CI/CD with the same code path, or continue locally for **k8s_platform**:
   ```bash
   cd infra/aws/k8s_platform
   terraform init -backend-config=../../examples/backend-k8s-platform.hcl
   # set -var for state_* and foundation_state_key to match foundation key
   terraform apply
   ```

## What is not stored in GitHub or AWS Secrets Manager here

- **EKS workload** secrets (Postgres app user, etc.) — still Kubernetes `Secret` objects reconciled by operators / Argo, per `plan.md`.
- **ACM private keys** — not used; ACM holds the cert.
- **Terraform state** — in **S3**; lock in **DynamoDB** (you manage those resources outside this list).

## CI image push

**`ci.yaml`** uses the repo’s **`GITHUB_TOKEN`** automatically (no extra secret) with **`permissions: packages: write`** to push to GHCR.
