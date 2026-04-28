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
| **`TF_STATE_BUCKET`** | `my-terraform-state-bucket` | S3 bucket for Terraform state. |
| **`TF_STATE_REGION`** | `us-east-1` | Region where the **state bucket and DynamoDB table** live (often same as EKS region). |
| **`TF_LOCK_TABLE`** | `my-terraform-locks` | DynamoDB table for state locking. |

### S3 state object keys (no variables)

Terraform workflows derive keys from the GitHub repository **short name** (`github.event.repository.name`, e.g. `kubernetes-mono-app`):

| Stack | S3 key |
|-------|--------|
| **foundation** | `<repo>/foundation/terraform.tfstate` |
| **k8s_platform** | `<repo>/k8s-platform/terraform.tfstate` |

The **k8s_platform** stack’s `foundation_state_key` input matches the foundation key so `terraform_remote_state` resolves correctly.

If you previously set **`TF_FOUNDATION_STATE_KEY`** or **`TF_K8S_PLATFORM_STATE_KEY`** as repository variables, you can delete them—workflows no longer read those.

**Local applies:** use the same pattern in `backend.hcl` / `-backend-config` / `-var foundation_state_key=…` (see `infra/aws/examples/`).

Optional convenience (not read by workflows today):

| Name | Example | Notes |
|------|---------|-------|
| **`EKS_CLUSTER_NAME`** | `k8s-mono` | Should match `cluster_name` in `infra/aws/foundation` — document only; bootstrap workflow still asks for cluster name unless you extend the workflow. |

## First-time chicken-and-egg

The **GitHub OIDC IAM roles** (`github_actions_terraform_role_arn` and `github_actions_bootstrap_role_arn`) are **created by the foundation stack**. Until they exist, GitHub Actions cannot assume them.

1. From your laptop (administrator or power-user AWS credentials), configure the S3 backend and run **foundation** only:
   ```bash
   cd infra/aws/foundation
   terraform init -backend-config=../../examples/backend-foundation.hcl  # copy/edit: key must be <repo>/foundation/terraform.tfstate
   export TF_VAR_aws_region=us-east-1
   export TF_VAR_github_organization=MichaelJ43
   export TF_VAR_github_repository=kubernetes-mono-app
   terraform apply
   ```
2. Copy **outputs** `github_actions_terraform_role_arn` → **`AWS_ROLE_ARN_TERRAFORM`**, `github_actions_bootstrap_role_arn` → **`AWS_ROLE_ARN_BOOTSTRAP`**.
3. Set the **Variables** `TF_STATE_BUCKET`, `TF_STATE_REGION`, `TF_LOCK_TABLE` in GitHub to match your backend.
4. Run **Terraform apply** workflow (`workflow_dispatch`, confirm `APPLY`) to align CI/CD with the same code path, or continue locally for **k8s_platform**:
   ```bash
   cd infra/aws/k8s_platform
   terraform init -backend-config=../../examples/backend-k8s-platform.hcl
   terraform apply \
     -var="aws_region=us-east-1" \
     -var="state_bucket=YOUR_BUCKET" \
     -var="state_region=us-east-1" \
     -var="lock_table=YOUR_TABLE" \
     -var="foundation_state_key=kubernetes-mono-app/foundation/terraform.tfstate"
   ```
   Use your real repo name in place of `kubernetes-mono-app` if it differs.

## What is not stored in GitHub or AWS Secrets Manager here

- **EKS workload** secrets (Postgres app user, etc.) — still Kubernetes `Secret` objects reconciled by operators / Argo, per `plan.md`.
- **ACM private keys** — not used; ACM holds the cert.
- **Terraform state** — in **S3**; lock in **DynamoDB** (you manage those resources outside this list).

## CI image push

**`ci.yaml`** uses the repo’s **`GITHUB_TOKEN`** automatically (no extra secret) with **`permissions: packages: write`** to push to GHCR.
