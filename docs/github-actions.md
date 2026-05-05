# GitHub Actions: secrets and variables

Configure these under **Settings → Secrets and variables → Actions** for the repository.

## Environments (`Settings → Environments`)

Workflows use two environments so you can scope **secrets**, **protection rules**, and **deployment branches** per concern:

| Environment | Workflows |
|-------------|-----------|
| **`build`** | **`ci.yaml`** — Go tests on push/PR. |
| **`deploy`** | **`deploy-aws.yaml`**, **`swap-stack.yaml`**, **`teardown-aws.yaml`**, **`terraform-apply.yaml`**, **`terraform-destroy.yaml`**, **`full-undeploy.yaml`**, **`soft-destroy.yaml`**, **`aws-full-destroy.yaml`**, **`argocd-bootstrap.yaml`**, **`argocd-teardown.yaml`**. |

Create **`build`** and **`deploy`** under **Settings → Environments**. Add **required reviewers** or **wait timers** on **`deploy`** for destructive paths. Repository secrets are available in environments unless you override with environment-specific secrets.

## SSM parameters

### `site_mode` (which stack the orchestrator targets)

Parameter name (String): **`/kubernetes-mono-app/site_mode`**

| Value | Meaning |
|-------|---------|
| **`cluster`** (default when the parameter is missing) | **`deploy-aws`** applies the **Kubernetes** objects from the release bundle (API + portal manifests) to EKS. |
| **`static`** | **`deploy-aws`** syncs **`static/cluster-offline`** from the bundle to the **parked** S3 bucket and invalidates CloudFront. |

**Who sets it**

- **`terraform-apply.yaml`** sets **`cluster`** after a successful apply (including Argo bootstrap).
- **`soft-destroy.yaml`** sets **`static`** after **`foundation`** destroy completes.
- **`swap-stack.yaml`** (orchestrator **POST /swap**) updates it when you change the active stack.

The deploy role needs **`ssm:GetParameter`** and **`ssm:PutParameter`** on **`/kubernetes-mono-app/*`** (AdministratorAccess includes this).

### `deploy_orchestrator_api_url`

Written by Terraform **`deploy_orchestrator`**: **`/kubernetes-mono-app/deploy_orchestrator_api_url`** — base URL of the HTTP API (**`POST /deploy`**, **`/swap`**, **`/teardown`**). Workflows read it with **`aws ssm get-parameter`**.

## Primary AWS workflows (three)

| Workflow | When | What |
|----------|------|------|
| **`deploy-aws.yaml`** | After **`CI`** succeeds on a push to **`main`**, or **`workflow_dispatch`** | Build/push API + portal to GHCR, render Kustomize into **`k8s/*.yaml`**, tarball with **`static/`**, upload to the orchestrator **source** S3 bucket, **`terraform apply`** **`infra/aws/deploy_orchestrator`**, **`POST /deploy`**, poll DynamoDB job status. |
| **`swap-stack.yaml`** | **`workflow_dispatch`** | **`POST /swap`** with optional inputs (`target`, `only_if_inactive`, `force_toggle`); poll job. |
| **`teardown-aws.yaml`** | **`workflow_dispatch`** (destructive) | **`POST /teardown`** with **`scope=both`**, poll, then **`terraform destroy`** **`deploy_orchestrator`** (removes source bucket, Lambda, API Gateway, etc.). |

## Platform lifecycle (still manual)

| What | How it runs |
|------|-------------|
| **EKS / VPC / IAM OIDC / Argo bootstrap** | **Actions → Terraform apply** — **`workflow_dispatch`** only; applies **`github_deploy`** → **`foundation`** → **`k8s_platform`**, then Argo CD Helm + root app; sets SSM **`site_mode=cluster`**. |
| **Parked site infra** (S3 + CloudFront) | Apply **`infra/aws/parked_site`** locally or via your process; **`deploy_orchestrator`** reads **parked_site** remote state (must exist **before** first orchestrator apply). |
| **Deploy orchestrator** (Lambda + source bucket + API) | First **`deploy-aws`** run (or manual **`terraform apply`** in **`infra/aws/deploy_orchestrator`**). |

## Secrets (`Settings → Secrets and variables → Actions → Secrets`)

| Name | Required | Used by |
|------|----------|---------|
| **`AWS_DEPLOY_ROLE_ARN`** | Yes (after the deploy role exists in IAM) | AWS OIDC workflows. Points at the **`github_deploy`** stack output **`github_actions_terraform_role_arn`** (same trust model as before). |
| **`TF_STATE_BUCKET`** | Yes | Terraform S3 backend `bucket`. |
| **`TF_LOCK_TABLE`** | Yes | DynamoDB state locking. |
| **`TF_STATE_REGION`** | No | Region of the state bucket and lock table; workflows default **`us-east-1`** when unset. |
| **`TF_ROUTE53_HOSTED_ZONE_ID`** | No | Route 53 **hosted zone ID** for your delegated **`k8s.…`** zone. Passed to **`k8s_platform`** (ExternalDNS). Used by **`parked_site`** when **`manage_route53_records`** is true (**`soft-destroy`**, **`aws-full-destroy`**). Required for automated DNS cutover on soft destroy. |
| **`TF_ACM_CERTIFICATE_ARN`** | Recommended for **`parked_site`** / HTTPS | Issued ACM cert ARN in **`us-east-1`** (same region as this repo’s ALB/CloudFront setup). Reused for **CloudFront** viewer cert and **foundation** output — **no separate CloudFront secret**. |

The **`github_deploy`** Terraform root creates the **`…-gha-terraform`** and **`…-gha-bootstrap`** IAM roles; **`foundation`** resolves their ARNs with **`aws_iam_role`** data sources (same naming convention) and attaches **EKS access entries** — no dependency on **`github_deploy`** state existing in S3 for plan or destroy.

If **`AWS_DEPLOY_ROLE_ARN`** is not the Terraform-managed terraform role, **`foundation`** still needs **`TF_VAR_github_actions_deploy_role_arn`** matching that secret so **EKS** grants **`k8s_platform`** Helm access.

### Terraform state keys (S3 object keys)

Derived from the repository **short name** (`github.event.repository.name`):

| Stack | S3 key |
|-------|--------|
| **github_deploy** | `<repo>/github-deploy/terraform.tfstate` |
| **foundation** | `<repo>/foundation/terraform.tfstate` |
| **k8s_platform** | `<repo>/k8s-platform/terraform.tfstate` |
| **parked_site** | `<repo>/parked-site/terraform.tfstate` |
| **deploy_orchestrator** | `<repo>/deploy-orchestrator/terraform.tfstate` |

**Bootstrap order for a new account / clone**

1. Apply **`github_deploy`** first (locally with backend config, or **`terraform-apply`**). Until those IAM roles exist (**`<cluster_name>-gha-terraform`** etc.), **`foundation`** cannot plan/apply (it looks up the roles by name).
2. **`terraform-apply.yaml`** (manual) runs **`github_deploy`** → **`foundation`** → **`k8s_platform`** → Argo CD + root app.
3. Apply **`parked_site`** at least once so its state includes **bucket** and **CloudFront** outputs (required by **`deploy_orchestrator`** remote state).
4. Run **`deploy-aws`** (or apply **`deploy_orchestrator`** manually) so the Lambda, source bucket, and HTTP API exist.

**Migrating from IAM embedded in `foundation`**

If your account already has **`github_deploy`**-equivalent IAM **inside** an older **`foundation`** state, you must **move** or **import** IAM into **`github_deploy`** state before switching **`foundation`** to remote state. Otherwise Terraform may try to recreate roles or conflict on names. Typical approach: `terraform state rm` the IAM resources from **`foundation`** after **`terraform import`** into **`github_deploy`**, or one-time admin recreation — treat as a breaking migration and run from a maintainer machine with backups.

### When **Terraform apply** runs

- **Manual** — **Actions → Terraform apply** (`workflow_dispatch`, no inputs).

It applies **`github_deploy`**, **`foundation`**, **`k8s_platform`**, then Argo CD Helm + root app, then writes SSM **`site_mode=cluster`**.

### Soft destroy (park EKS, keep GitHub IAM)

- **Actions → Soft destroy** (`workflow_dispatch`, no inputs). Cluster and region follow **`EKS_CLUSTER_NAME`** / **`TF_STATE_REGION`** (same defaults as **Terraform apply**). Parks **S3 + CloudFront**, uploads static mocks, deletes Ingresses and Argo, waits, then applies **Route53 → CloudFront** if **`TF_ROUTE53_HOSTED_ZONE_ID`** is set, then **`terraform destroy`** on **`k8s_platform`** and **`foundation`**. Does **not** destroy **`github_deploy`** or **`parked_site`**.

### Full AWS destroy (stack cleanup)

- **`terraform-destroy.yaml`** — **`k8s_platform`** then **`foundation`** only (no parked stack); **`workflow_dispatch`** with no inputs (gate with **`deploy`** environment rules).
- **`aws-full-destroy.yaml`** — **`k8s_platform`**, **`foundation`**, **`parked_site`**, each **`continue-on-error`**. Does **not** destroy **`github_deploy`**. No workflow inputs.

### Full undeploy (legacy naming)

- **Full undeploy** — Argo / root app cleanup via **`kubectl`** / **`helm`**, then **`k8s_platform`** then **`foundation`** (no workflow inputs; cluster/region from **`EKS_CLUSTER_NAME`** / **`TF_STATE_REGION`**). If the API is already gone, use **`terraform-destroy`** instead.

## Variables (`Settings → Secrets and variables → Actions → Variables`)

Optional convenience:

| Name | Example | Notes |
|------|---------|-------|
| **`EKS_CLUSTER_NAME`** | same as foundation `cluster_name` | Used by **`soft-destroy`**, **`full-undeploy`**, and **`github_deploy`** **`TF_VAR_cluster_name`** in **`terraform-apply`**; defaults to **`k8s-mono`** when unset. |
| **`EKS_AWS_REGION`** | `us-east-1` | Optional; region hints for scripts if you add them. |

**`terraform-apply.yaml`** uses **`EKS_CLUSTER_NAME`** (or **`k8s-mono`**) for **`TF_VAR_cluster_name`** on **`github_deploy`** so IAM role names stay aligned with **`foundation`**.

## First-time chicken-and-egg

GitHub OIDC IAM is created by **`github_deploy`**, not **`foundation`**. Until **`github_deploy`** is applied and **`AWS_DEPLOY_ROLE_ARN`** is set to **`github_actions_terraform_role_arn`**, Actions cannot assume the deploy role.

1. Configure S3 backend and run **`github_deploy`** (same bucket/key pattern as above).
2. Set **`AWS_DEPLOY_ROLE_ARN`**, **`TF_STATE_BUCKET`**, **`TF_LOCK_TABLE`**.
3. Run **`terraform-apply.yaml`** from **Actions**, or apply **`foundation`** / **`k8s_platform`** locally using **`infra/aws/examples/`**.
4. Apply **`parked_site`**, then use **`deploy-aws`** for ongoing releases.

## CI and deploy-aws

**`ci.yaml`** runs tests on push/PR. On **`main`**, when **CI** completes successfully, **`deploy-aws`** runs (same repo, **`workflow_run`**). It does **not** commit Kustomize image tag changes to Git; tags are set in the runner and baked into the bundle only.

Repository **Actions → General → Workflow permissions** must allow **packages: write** (default **`GITHUB_TOKEN`**) for GHCR pushes from **`deploy-aws`**.

## What is not stored in GitHub or AWS Secrets Manager here

- **EKS workload** secrets — Kubernetes **`Secret`** objects, per **`plan.md`**.
- **ACM private keys** — ACM holds the cert.
- **Terraform state** — S3; lock in **DynamoDB**.

## Troubleshooting (subset)

1. **`foundation` plan/apply: GitHub IAM roles missing** — Run **`github_deploy`** apply first so **`…-gha-terraform`** / **`…-gha-bootstrap`** exist (role names use the same **`cluster_name`** as **`foundation`**).

2. **`parked_site` / static deploy: invalid ACM** — CloudFront requires an **ISSUED** cert in **`us-east-1`** covering your **`parked_aliases`**. Reuse **`TF_ACM_CERTIFICATE_ARN`** when it already points at that cert.

3. **`deploy_orchestrator` plan/apply fails on remote state** — Ensure **`parked_site`** state exists in S3 and has been **re-applied** at least once after outputs (**`s3_bucket_id`**, **`cloudfront_distribution_id`**) were added.

4. **Fork PRs** — OIDC plan jobs only run for same-repo PRs. **`validate`** (fmt/validate) still runs.

5. **EKS access** — Deploy role must have an **EKS access entry**; **`foundation`** wires **`AWS_DEPLOY_ROLE_ARN`** via **`github_deploy`** role ARNs. The orchestrator Lambda gets its own access entry from **`deploy_orchestrator`**.

6. **`terraform plan` on PR** — If **`github_deploy`** state is **missing** in S3, the **foundation** plan step is **skipped** (notice in logs) so the PR stays green; run **`github_deploy`** / **Terraform apply** once, then re-run the plan check.
