# Post-merge: bring-up checklist

Order to go from **merged repo** to **API reachable on your domain** on AWS. Automation does not replace your AWS Console steps for Route 53 / ACM where noted.

## 0. Prerequisites

- **S3 bucket** and **DynamoDB table** for Terraform state (you create these once per account; names are yours).
- In GitHub: **Actions secrets** from [`github-actions.md`](github-actions.md):
  - `AWS_DEPLOY_ROLE_ARN`
  - `TF_STATE_BUCKET`, `TF_LOCK_TABLE`, optional `TF_STATE_REGION`
- Fork or rename? Update `repoURL` in `deploy/gitops/**/*.yaml` and image references per [`README.md`](../README.md).

## 1. Terraform: foundation

Create VPC, EKS, OIDC roles, EBS CSI, etc.

**Locally** (see [`infra/aws/README.md`](../infra/aws/README.md)):

```bash
cd infra/aws/foundation
# backend.hcl / tfvars per examples/
terraform init -backend-config=...
terraform apply
```

**Or** use **Actions → Terraform apply** after secrets exist (confirm `APPLY`).

**Copy outputs:** `cluster_name`, `aws_region`, `github_actions_terraform_role_arn` → ensure `AWS_DEPLOY_ROLE_ARN` matches your single deploy role.

Foundation **state object** must exist in S3 before `k8s_platform` can run.

## 2. Terraform: k8s_platform

Installs **AWS Load Balancer Controller** (Helm) using foundation remote state.

```bash
cd infra/aws/k8s_platform
terraform init -backend-config=...   # key: <repo>/k8s-platform/terraform.tfstate
terraform apply
```

Or the same **Terraform apply** workflow (runs foundation then k8s_platform).

## 3. Domain, ACM, DNS

Follow **[`aws-domain-tls.md`](aws-domain-tls.md)** (hosted zone, ACM in **ALB region**, validation records).

## 4. Ingress: set ACM ARN in Git

The Argo **API** app uses **`deploy/overlays/aws-prod`**, so you only patch **`deploy/overlays/aws-prod/ingress-acm-patch.yaml`**: set `alb.ingress.kubernetes.io/certificate-arn` to your real ACM certificate ARN (same region as the cluster / ALB).

Commit to `main` (or merge a PR) **before** or **after** Argo bootstrap; Argo will sync the change.

## 5. Image on GHCR

Merge or push to **`main`** so **[`ci.yaml`](../.github/workflows/ci.yaml)** runs tests and **pushes** `ghcr.io/<lowercase-owner>/kubernetes-mono-app/api:latest`.

If the package is **private**, configure pull access (e.g. `imagePullSecrets` / GHCR PAT) — see [`runbooks/bootstrap.md`](runbooks/bootstrap.md).

## 6. Argo CD bootstrap

1. **Actions → Argo CD bootstrap** (`argocd-bootstrap.yaml`).
2. Inputs: `cluster_name` and `aws_region` match Terraform outputs.
3. Workflow installs Argo (`infra/argocd/values.yaml`), then `kubectl apply -f deploy/gitops/root-app.yaml`.

**Admin password / UI:** see [`runbooks/bootstrap.md`](runbooks/bootstrap.md).

## 7. DNS record for the API hostname

When the **Ingress** provisions an ALB, create **Route 53** (in `k8s.michaelj43.dev` or your zone) an **alias** (or CNAME) from **`api.k8s…`** → ALB hostname (`kubectl -n portfolio get ingress api`).

## 8. Verify

```bash
kubectl get applications -n argocd
kubectl -n portfolio get pods,ingress
curl -fsS https://api.k8s.michaelj43.dev/health   # host from your Ingress
```

## 9. If something fails

- **Terraform / OIDC:** [`github-actions.md`](github-actions.md) troubleshooting.
- **Remote state / k8s_platform:** ensure foundation **apply** finished and PR CI allows `k8s_platform` plan (state in S3).
- **503 / TLS:** [`aws-domain-tls.md`](aws-domain-tls.md) table.

## 10. Teardown

[`runbooks/teardown.md`](runbooks/teardown.md) (destroy order: platform stack, then foundation; Argo teardown workflow if used).
