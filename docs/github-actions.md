# GitHub Actions: secrets and variables

Configure these under **Settings → Secrets and variables → Actions** for the repository.

## Environments (`Settings → Environments`)

Workflows use two environments so you can scope **secrets**, **protection rules**, and **deployment branches** per concern:

| Environment | Workflows |
|-------------|-----------|
| **`build`** | **`ci.yaml`** — Go tests only. **`kubernetes-images.yaml`** — manual GHCR build, Kustomize pin, optional rollout. |
| **`deploy`** | **`deploy-main.yaml`**, **`terraform-apply.yaml`**, **`terraform-destroy.yaml`**, **`full-undeploy.yaml`**, **`static-site-deploy.yaml`**, **`soft-destroy.yaml`**, **`aws-full-destroy.yaml`**, **`argocd-bootstrap.yaml`**, **`argocd-teardown.yaml`**. |

Create **`build`** and **`deploy`** under **Settings → Environments**. Add **required reviewers** or **wait timers** on **`deploy`** for destructive paths. Repository secrets are available in environments unless you override with environment-specific secrets.

## SSM `site_mode` (auto deploy on merge to `main`)

Parameter name (String): **`/kubernetes-mono-app/site_mode`**

| Value | Meaning |
|-------|---------|
| **`cluster`** (default when parameter is missing) | Live EKS: **`deploy-main`** runs **`terraform-apply`** only when **`infra/aws/**`** (or related workflow files) change. **Argo CD** still reconciles app changes from Git without a deploy workflow. |
| **`static`** | Parked mode: **`deploy-main`** runs **`static-site-deploy`** only when **`static/cluster-offline/**`**, **`infra/aws/parked_site/**`**, or the static workflow file change. |

**Who sets it**

- **`terraform-apply.yaml`** (manual or called from **`deploy-main`**) sets **`cluster`** after a successful apply (including Argo bootstrap).
- **`soft-destroy.yaml`** sets **`static`** after **`foundation`** destroy completes.

The deploy role needs **`ssm:GetParameter`** and **`ssm:PutParameter`** on that name (AdministratorAccess includes this).

## Default vs manual deploy paths

| What | How it runs |
|------|-------------|
| **Push to `main` (routed)** | **`deploy-main.yaml`** reads SSM, then calls **`terraform-apply`** or **`static-site-deploy`** via **`workflow_call`** when paths match (see above). |
| **Redeploy on `main` without a diff** | **Actions → Deploy main** (`workflow_dispatch`, no inputs) — treats infra and static paths as changed so the matching child workflow(s) run for the current SSM **`site_mode`**. |
| **Static parked site** (manual) | **Actions → Static site deploy** — same steps as the static branch of **`deploy-main`** (no workflow inputs). |
| **EKS / Terraform / Argo** (manual) | **Actions → Terraform apply** — same stack as **`deploy-main`**’s cluster path; no form inputs (region from **`TF_STATE_REGION`**, cluster from **`EKS_CLUSTER_NAME`** / default **`k8s-mono`**). |
| **Images + Kustomize pin** | **`kubernetes-images.yaml`** (`workflow_dispatch`). |

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

**Bootstrap order for a new account / clone**

1. Apply **`github_deploy`** first (locally with backend config, or **`terraform-apply`**). Until those IAM roles exist (**`<cluster_name>-gha-terraform`** etc.), **`foundation`** cannot plan/apply (it looks up the roles by name).
2. **`terraform-apply.yaml`** (manual) runs **`github_deploy`** → **`foundation`** → **`k8s_platform`** → Argo CD + root app.

**Migrating from IAM embedded in `foundation`**

If your account already has **`github_deploy`**-equivalent IAM **inside** an older **`foundation`** state, you must **move** or **import** IAM into **`github_deploy`** state before switching **`foundation`** to remote state. Otherwise Terraform may try to recreate roles or conflict on names. Typical approach: `terraform state rm` the IAM resources from **`foundation`** after **`terraform import`** into **`github_deploy`**, or one-time admin recreation — treat as a breaking migration and run from a maintainer machine with backups.

### When **Terraform apply** runs

- **Manual** — **Actions → Terraform apply** (`workflow_dispatch`, no inputs).
- **Automatic** — **`deploy-main`** calls it on push to **`main`** (or manual **`deploy-main`**) when SSM **`site_mode`** is **`cluster`** and path filters show **infra** changes.

In both cases it applies **`github_deploy`**, **`foundation`**, **`k8s_platform`**, then Argo CD Helm + root app, then writes SSM **`site_mode=cluster`**.

### Static site deploy

- **Actions → Static site deploy** (`workflow_dispatch`) — same steps as **`deploy-main`** when SSM **`site_mode=static`** and static paths change.
- Applies **`parked_site`** (no Route53 record management by default), uploads assets with correct **`Content-Type`** for **`.json`**, invalidates CloudFront.

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
| **`EKS_CLUSTER_NAME`** | same as foundation `cluster_name` | Used by **`kubernetes-images`** rollout, **`soft-destroy`**, **`full-undeploy`**, and **`github_deploy`** **`TF_VAR_cluster_name`** in **`terraform-apply`**; defaults to **`k8s-mono`** when unset. |
| **`EKS_AWS_REGION`** | `us-east-1` | Region for **`aws eks update-kubeconfig`** in **`kubernetes-images`**. |

**`terraform-apply.yaml`** uses **`EKS_CLUSTER_NAME`** (or **`k8s-mono`**) for **`TF_VAR_cluster_name`** on **`github_deploy`** so IAM role names stay aligned with **`foundation`**.

## First-time chicken-and-egg

GitHub OIDC IAM is created by **`github_deploy`**, not **`foundation`**. Until **`github_deploy`** is applied and **`AWS_DEPLOY_ROLE_ARN`** is set to **`github_actions_terraform_role_arn`**, Actions cannot assume the deploy role.

1. Configure S3 backend and run **`github_deploy`** (same bucket/key pattern as above).
2. Set **`AWS_DEPLOY_ROLE_ARN`**, **`TF_STATE_BUCKET`**, **`TF_LOCK_TABLE`**.
3. Run **`terraform-apply.yaml`** from **Actions**, or apply **`foundation`** / **`k8s_platform`** locally using **`infra/aws/examples/`**.

## CI image push and deploy pins (manual)

**`kubernetes-images.yaml`** is **`workflow_dispatch`** only: build/push API and portal to GHCR, **`kustomize edit set image`**, commit **`[skip ci]`**, optional **`rollout`** when **`EKS_CLUSTER_NAME`** is set.

Repository **Actions → General → Workflow permissions** must allow **read and write** for **`pin-images`** to push the commit.

## What is not stored in GitHub or AWS Secrets Manager here

- **EKS workload** secrets — Kubernetes **`Secret`** objects, per **`plan.md`**.
- **ACM private keys** — ACM holds the cert.
- **Terraform state** — S3; lock in **DynamoDB**.

## Troubleshooting (subset)

1. **`foundation` plan/apply: GitHub IAM roles missing** — Run **`github_deploy`** apply first so **`…-gha-terraform`** / **`…-gha-bootstrap`** exist (role names use the same **`cluster_name`** as **`foundation`**).

2. **`parked_site` / static deploy: invalid ACM** — CloudFront requires an **ISSUED** cert in **`us-east-1`** covering your **`parked_aliases`**. Reuse **`TF_ACM_CERTIFICATE_ARN`** when it already points at that cert.

3. **Fork PRs** — OIDC plan jobs only run for same-repo PRs. **`validate`** (fmt/validate) still runs.

4. **EKS access** — Deploy role must have an **EKS access entry**; **`foundation`** wires **`AWS_DEPLOY_ROLE_ARN`** via **`github_deploy`** role ARNs.

5. **`terraform plan` on PR** — If **`github_deploy`** state is **missing** in S3, the **foundation** plan step is **skipped** (notice in logs) so the PR stays green; run **`github_deploy`** / **Terraform apply** once, then re-run the plan check.
