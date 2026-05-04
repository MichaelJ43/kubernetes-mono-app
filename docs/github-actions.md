# GitHub Actions: secrets and variables

Configure these under **Settings → Secrets and variables → Actions** for the repository.

## Environments (`Settings → Environments`)

Workflows use two environments so you can scope **secrets**, **protection rules**, and **deployment branches** per concern:

| Environment | Workflows |
|-------------|-----------|
| **`build`** | **`ci.yaml`** — Go tests only. **`kubernetes-images.yaml`** — manual GHCR build, Kustomize pin, optional rollout. |
| **`deploy`** | **`terraform-apply.yaml`**, **`terraform-destroy.yaml`**, **`full-undeploy.yaml`**, **`static-site-deploy.yaml`**, **`soft-destroy.yaml`**, **`aws-full-destroy.yaml`**, **`argocd-bootstrap.yaml`**, **`argocd-teardown.yaml`**. |

Create **`build`** and **`deploy`** under **Settings → Environments**. Add **required reviewers** or **wait timers** on **`deploy`** for destructive paths. Repository secrets are available in environments unless you override with environment-specific secrets.

## Default vs manual deploy paths

| What | How it runs |
|------|-------------|
| **Static parked site** (S3 + CloudFront + `static/cluster-offline`) | **Push to `main`** when files under **`static/cluster-offline/**` or **`infra/aws/parked_site/**`** change — workflow **`static-site-deploy.yaml`**. |
| **EKS / Terraform / Argo** | **Manual** — run **`terraform-apply.yaml`** (confirm **`APPLY`**). Images + Kustomize pin — **`kubernetes-images.yaml`** (`workflow_dispatch`). |

## Secrets (`Settings → Secrets and variables → Actions → Secrets`)

| Name | Required | Used by |
|------|----------|---------|
| **`AWS_DEPLOY_ROLE_ARN`** | Yes (after the deploy role exists in IAM) | AWS OIDC workflows. Points at the **`github_deploy`** stack output **`github_actions_terraform_role_arn`** (same trust model as before). |
| **`TF_STATE_BUCKET`** | Yes | Terraform S3 backend `bucket`. |
| **`TF_LOCK_TABLE`** | Yes | DynamoDB state locking. |
| **`TF_STATE_REGION`** | No | Region of the state bucket and lock table; workflows default **`us-east-1`** when unset. |
| **`TF_ROUTE53_HOSTED_ZONE_ID`** | No | Route 53 **hosted zone ID** for your delegated **`k8s.…`** zone. Passed to **`k8s_platform`** (ExternalDNS). Used by **`parked_site`** when **`manage_route53_records`** is true (**`soft-destroy`**, **`aws-full-destroy`**). Required for automated DNS cutover on soft destroy. |
| **`TF_ACM_CERTIFICATE_ARN`** | Recommended for **`parked_site`** / HTTPS | Issued ACM cert ARN in **`us-east-1`** (same region as this repo’s ALB/CloudFront setup). Reused for **CloudFront** viewer cert and **foundation** output — **no separate CloudFront secret**. |

The **`github_deploy`** Terraform root creates **`github_actions_terraform_role_arn`** and **`github_actions_bootstrap_role_arn`**; **`foundation`** reads that state via remote state and attaches **EKS access entries** only.

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

1. Apply **`github_deploy`** first (locally with backend config, or add a one-off workflow). Until **`github_deploy`** state exists in S3, **`foundation`** cannot plan/apply (remote state).
2. **`terraform-apply.yaml`** (manual) runs **`github_deploy`** → **`foundation`** → **`k8s_platform`** → Argo CD + root app.

**Migrating from IAM embedded in `foundation`**

If your account already has **`github_deploy`**-equivalent IAM **inside** an older **`foundation`** state, you must **move** or **import** IAM into **`github_deploy`** state before switching **`foundation`** to remote state. Otherwise Terraform may try to recreate roles or conflict on names. Typical approach: `terraform state rm` the IAM resources from **`foundation`** after **`terraform import`** into **`github_deploy`**, or one-time admin recreation — treat as a breaking migration and run from a maintainer machine with backups.

### When **Terraform apply** runs

- **Manual only** — **Actions → Terraform apply**, confirm **`APPLY`**. Applies **`github_deploy`**, **`foundation`**, **`k8s_platform`**, then Argo CD Helm + root app.

### Static site deploy (**default on relevant pushes**)

- **Actions → Static site deploy** also runs on **push to `main`** for **`static/cluster-offline/**` and **`infra/aws/parked_site/**`**. Applies **`parked_site`** (no Route53 record management by default), uploads assets with correct **`Content-Type`** for **`.json`**, invalidates CloudFront.

### Soft destroy (park EKS, keep GitHub IAM)

- **Actions → Soft destroy**: confirm **`SOFT DESTROY`**, set cluster name and region. Parks **S3 + CloudFront**, uploads static mocks, deletes Ingresses (and optionally Argo), waits, then applies **Route53 → CloudFront** if **`TF_ROUTE53_HOSTED_ZONE_ID`** is set, then **`terraform destroy`** on **`k8s_platform`** and **`foundation`**. Does **not** destroy **`github_deploy`** or **`parked_site`**.

### Full AWS destroy (stack cleanup)

- **`terraform-destroy.yaml`** — **`k8s_platform`** then **`foundation`** only (no parked stack).
- **`aws-full-destroy.yaml`** — **`k8s_platform`**, **`foundation`**, **`parked_site`**, each **`continue-on-error`**. Does **not** destroy **`github_deploy`**.

### Full undeploy (legacy naming)

- **Full undeploy**: confirm **`FULL UNDEPLOY`**, cluster / region; optional Argo cleanup; **`k8s_platform`** then **`foundation`** (same as **`terraform-destroy`** with optional kubectl).

## Variables (`Settings → Secrets and variables → Actions → Variables`)

Optional convenience:

| Name | Example | Notes |
|------|---------|-------|
| **`EKS_CLUSTER_NAME`** | same as foundation `cluster_name` | Optional **`kubernetes-images`** rollout: **`kubectl apply`** after **`pin-images`**. |
| **`EKS_AWS_REGION`** | `us-east-1` | Region for **`aws eks update-kubeconfig`** in **`kubernetes-images`**. |

**`terraform-apply.yaml`** uses **`EKS_CLUSTER_NAME`** (or **`k8s-mono`**) for **`TF_VAR_cluster_name`** on **`github_deploy`** so IAM role names stay aligned with **`foundation`**.

## First-time chicken-and-egg

GitHub OIDC IAM is created by **`github_deploy`**, not **`foundation`**. Until **`github_deploy`** is applied and **`AWS_DEPLOY_ROLE_ARN`** is set to **`github_actions_terraform_role_arn`**, Actions cannot assume the deploy role.

1. Configure S3 backend and run **`github_deploy`** (same bucket/key pattern as above).
2. Set **`AWS_DEPLOY_ROLE_ARN`**, **`TF_STATE_BUCKET`**, **`TF_LOCK_TABLE`**.
3. Run **`terraform-apply.yaml`** with **`APPLY`**, or apply **`foundation`** / **`k8s_platform`** locally using **`infra/aws/examples/`**.

## CI image push and deploy pins (manual)

**`kubernetes-images.yaml`** is **`workflow_dispatch`** only: build/push API and portal to GHCR, **`kustomize edit set image`**, commit **`[skip ci]`**, optional **`rollout`** when **`EKS_CLUSTER_NAME`** is set.

Repository **Actions → General → Workflow permissions** must allow **read and write** for **`pin-images`** to push the commit.

## What is not stored in GitHub or AWS Secrets Manager here

- **EKS workload** secrets — Kubernetes **`Secret`** objects, per **`plan.md`**.
- **ACM private keys** — ACM holds the cert.
- **Terraform state** — S3; lock in **DynamoDB**.

## Troubleshooting (subset)

1. **`foundation` plan/apply: remote state for `github_deploy` missing** — Run **`github_deploy`** apply first so the state object exists in the bucket.

2. **`parked_site` / static deploy: invalid ACM** — CloudFront requires an **ISSUED** cert in **`us-east-1`** covering your **`parked_aliases`**. Reuse **`TF_ACM_CERTIFICATE_ARN`** when it already points at that cert.

3. **Fork PRs** — OIDC plan jobs only run for same-repo PRs. **`validate`** (fmt/validate) still runs.

4. **EKS access** — Deploy role must have an **EKS access entry**; **`foundation`** wires **`AWS_DEPLOY_ROLE_ARN`** via **`github_deploy`** role ARNs.

5. **`terraform plan` on PR** — **`foundation`** needs **`github_deploy`** state in S3; otherwise plan fails until bootstrap step **1** is done.
