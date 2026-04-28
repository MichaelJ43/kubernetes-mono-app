# GitHub Actions: secrets and variables

Configure these under **Settings → Secrets and variables → Actions** for the repository.

## Secrets (`Settings → Secrets and variables → Actions → Secrets`)

| Name | Required | Used by |
|------|----------|---------|
| **`AWS_DEPLOY_ROLE_ARN`** | Yes (after the deploy role exists in IAM) | **All** AWS OIDC workflows: `terraform-plan.yaml`, `terraform-apply.yaml`, `terraform-destroy.yaml`, `argocd-bootstrap.yaml`, `argocd-teardown.yaml`. Set to the ARN of **one** IAM role that can run Terraform and EKS bootstrap/teardown (e.g. foundation output `github_actions_terraform_role_arn`, or your own equivalent role). |
| **`TF_STATE_BUCKET`** | Yes | Terraform workflows — S3 bucket for remote state (backend `bucket`). |
| **`TF_LOCK_TABLE`** | Yes | Terraform workflows — DynamoDB table for state locking (`dynamodb_table`). |
| **`TF_STATE_REGION`** | No | Region where the **state bucket and lock table** live; if unset, workflows default **`us-east-1`** for backend region and `aws configure`. |

Foundation also outputs `github_actions_bootstrap_role_arn` (narrower GitOps-only role). You can ignore it if you use a single full-permission deploy role as above.

## Variables (`Settings → Secrets and variables → Actions → Variables`)

Repository **variables** are optional for this repo’s workflows. Terraform reads state backend settings from **secrets** above.

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

The **GitHub OIDC IAM roles** (at least `github_actions_terraform_role_arn`, and optionally `github_actions_bootstrap_role_arn`) are **created by the foundation stack**. Until your chosen deploy role exists, GitHub Actions cannot assume **`AWS_DEPLOY_ROLE_ARN`**.

1. From your laptop (administrator or power-user AWS credentials), configure the S3 backend and run **foundation** only:
   ```bash
   cd infra/aws/foundation
   terraform init -backend-config=../../examples/backend-foundation.hcl  # copy/edit: key must be <repo>/foundation/terraform.tfstate
   export TF_VAR_aws_region=us-east-1
   export TF_VAR_github_organization=MichaelJ43
   export TF_VAR_github_repository=kubernetes-mono-app
   terraform apply
   ```
2. Copy the ARN of your **deploy role** into **`AWS_DEPLOY_ROLE_ARN`** (e.g. output `github_actions_terraform_role_arn` if that role has permissions for Terraform and cluster bootstrap).
3. Set **Secrets** `TF_STATE_BUCKET`, `TF_LOCK_TABLE`, and optionally `TF_STATE_REGION` in GitHub to match your backend.
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

## Troubleshooting: Terraform plan + OIDC (“Could not load credentials”)

1. **`AWS_DEPLOY_ROLE_ARN` empty** — Terraform plan fails fast with a clear error. Set the secret to your deploy role ARN (commonly output `github_actions_terraform_role_arn`). Argo workflows need the same secret.

2. **IAM trust `sub` mismatch** — The role must trust GitHub’s OIDC subject for **pull requests**, e.g. `repo:YOUR_ORG/YOUR_REPO:pull_request` (and branch pushes). This repo’s Terraform allows `repo:<org>/<repo>:*` plus **lowercase org/repo** variants so `MichaelJ43` vs `michaelj43` does not break STS. After changing `iam_github_oidc.tf`, run **`terraform apply`** on **foundation** and wait for IAM to update.

3. **Fork PRs** — Secrets are not available on workflows triggered from forks. The **plan** jobs only run when `pull_request.head.repo.fork == false`. **fmt/validate** still runs.

4. **Repo Settings → Actions → General** — Workflow permissions must allow **read** (and **OIDC** is standard for GHA). Ensure Actions are enabled for the repository.

5. **Backend secrets** — `TF_STATE_BUCKET` and `TF_LOCK_TABLE` must be set (repository **Secrets**). If either is empty, `terraform init` fails with *The value cannot be empty or all whitespace* on the S3 backend `bucket` / `dynamodb_table` line; workflows fail earlier with an explicit error.
