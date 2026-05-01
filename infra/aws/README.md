# AWS foundation (Terraform)

Two stacks share one **S3 backend** (different keys) and one **DynamoDB** lock table.

| Stack | Path | What it creates |
|-------|------|------------------|
| **foundation** | `infra/aws/foundation` | VPC, EKS (see `cluster_version` default in `variables.tf`), managed nodes, `aws-ebs-csi-driver` addon, GitHub OIDC IAM roles (Terraform + bootstrap), IRSA role for AWS LB Controller, EKS access entries for both GitHub roles. |
| **k8s_platform** | `infra/aws/k8s_platform` | **Helm**: `aws-load-balancer-controller` into `kube-system`; optional **ExternalDNS** when **`TF_ROUTE53_HOSTED_ZONE_ID`** (CI) / **`external_dns_route53_zone_id`** (local) is set (Ingress → Route 53 aliases). |

**Argo CD** (install + app manifests) stays **inside the cluster** after bootstrap — Terraform does not install Argo.

## Prerequisites

- AWS account, `aws` CLI configured for first apply.
- **S3 bucket** + **DynamoDB table** for Terraform state (you already have these).
- GitHub repo **Secrets** for Terraform/AWS (see [`../docs/github-actions.md`](../docs/github-actions.md)).
- For **automatic DNS** under your delegated zone (e.g. `api.k8s.…` → ALB): set repository **Secret** **`TF_ROUTE53_HOSTED_ZONE_ID`** to the Route 53 **hosted zone ID** of `k8s.yourdomain` (see [`../docs/aws-domain-tls.md`](../docs/aws-domain-tls.md)).

**EKS control plane upgrades:** AWS allows only **one minor version per apply** (for example 1.29 → 1.30, then a later apply 1.30 → 1.31). If apply fails with `Unsupported Kubernetes minor version update`, adjust `cluster_version` in `variables.tf` / `terraform.tfvars` to the next minor only.

**EBS CSI add-on:** The managed `aws-ebs-csi-driver` add-on needs an **IRSA role** (`module.ebs_csi_irsa` in `eks.tf`). Without `service_account_role_arn`, the add-on can sit in `CREATING` until Terraform times out. If a failed run left a stuck add-on in AWS, delete it once (`aws eks delete-addon --cluster-name … --addon-name aws-ebs-csi-driver`) and re-apply.

## First apply (local)

1. Copy `examples/backend-foundation.hcl.example` → `backend.hcl` (gitignored path recommended: store outside repo or use `-backend-config` flags).
2. Copy `examples/foundation/terraform.tfvars.example` → `terraform.tfvars` (gitignored) or export `TF_VAR_*`.
3. From `infra/aws/foundation`:
   ```bash
   terraform init -backend-config=backend.hcl
   terraform apply
   ```
   Optional: set **`acm_certificate_arn`** or **`acm_certificate_domain`** in `terraform.tfvars` if you want **`terraform output acm_certificate_arn`** for your own records (not required for Argo—Ingress uses ALB **certificate discovery**; CI can use secret **`TF_ACM_CERTIFICATE_ARN`**; see [`../docs/aws-domain-tls.md`](../docs/aws-domain-tls.md)).
4. Set GitHub **Secrets**: `AWS_DEPLOY_ROLE_ARN` (deploy role, usually `github_actions_terraform_role_arn`); `TF_STATE_BUCKET`, `TF_LOCK_TABLE`, and optionally `TF_STATE_REGION` — see [`../docs/github-actions.md`](../docs/github-actions.md). Optional narrow role `github_actions_bootstrap_role_arn` exists if you split IAM roles.
5. From `infra/aws/k8s_platform`, use a second key **`<repo>/k8s-platform/terraform.tfstate`** (same repo short name as in step 1) **or** pass backend flags and:
   ```bash
   terraform init -backend-config=backend.hcl
   terraform apply \
     -var="aws_region=us-east-1" \
     -var="state_bucket=YOUR_BUCKET" \
     -var="state_region=us-east-1" \
     -var="lock_table=YOUR_TABLE" \
     -var="foundation_state_key=kubernetes-mono-app/foundation/terraform.tfstate"
   ```
   Replace `kubernetes-mono-app` with your repository name if different; it must match the foundation state key prefix.

After that, use **GitHub Actions → Terraform apply** for repeatability.

## Destroy order

1. **k8s_platform** (`terraform destroy` or workflow **Terraform destroy** — it runs platform first).
2. **foundation**.

## Cost notes

- Default **`enable_nat_gateway = false`** places nodes in **public** subnets to avoid NAT charges (portfolio only).
- Flip `enable_nat_gateway = true` in `terraform.tfvars` for private nodes + NAT.

## Files

- Provider lock files: `foundation/.terraform.lock.hcl`, `k8s_platform/.terraform.lock.hcl` (commit these).
