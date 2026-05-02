# Runbook: Bootstrap

**End-to-end order (Terraform → DNS → Argo):** [`../post-merge-runbook.md`](../post-merge-runbook.md).

## 0. Terraform (VPC + EKS + LB controller + GitHub OIDC roles)

Use **Terraform** for the **Kubernetes platform** the cluster runs on. Argo CD does **not** create EKS.

See **[`infra/aws/README.md`](../../infra/aws/README.md)** and **[`docs/github-actions.md`](../../docs/github-actions.md)** for:

- S3 + DynamoDB state/lock
- **Secrets**: `AWS_DEPLOY_ROLE_ARN`, `TF_STATE_BUCKET`, `TF_LOCK_TABLE` (optional `TF_STATE_REGION`)

**Order:** `foundation` apply → `k8s_platform` apply (or use **Terraform apply** workflow after GitHub secrets exist).

**First time:** run **foundation** (and optionally **k8s_platform**) **locally** with admin AWS credentials so OIDC roles are created; then paste role ARNs into GitHub Secrets.

## 1. GitHub → AWS (OIDC)

After Terraform foundation apply, set:

- **`AWS_DEPLOY_ROLE_ARN`** → your single deploy role (often `github_actions_terraform_role_arn` from foundation)
- **`TF_STATE_BUCKET`**, **`TF_LOCK_TABLE`**, optionally **`TF_STATE_REGION`** → match your S3/DynamoDB backend (see `docs/github-actions.md`)

## 2. Install Argo CD

- **CI:** workflow **Argo CD bootstrap** (`argocd-bootstrap.yaml`) — use the **same** `cluster_name` and `aws_region` as Terraform (`cluster_name` output / `aws_region` variable).
- **Locally:**

  ```bash
  aws eks update-kubeconfig --name YOUR_CLUSTER --region YOUR_REGION
  helm repo add argo https://argoproj.github.io/argo-helm
  helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace -f infra/argocd/values.yaml
  kubectl apply -f deploy/gitops/root-app.yaml
  ```

## 3. Initial admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Port-forward UI (when ingress is disabled):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

**Public UI (Helm values in `infra/argocd/values.yaml`):** With **`server.ingress.enabled`** and **`global.domain`** set (e.g. `argo.k8s.michaelj43.dev`), the AWS Load Balancer Controller provisions an internet-facing ALB; **ExternalDNS** creates the hostname in Route 53 once the Ingress has an address. Open **`https://argo.k8s.michaelj43.dev/`** (same ACM / wildcard zone requirements as `docs/aws-domain-tls.md`). Treat **`admin`** as break-glass on the public internet.

## 4. Verify workloads

In Argo CD (or `kubectl`):

- `cnpg-system` — operator running
- `portfolio` — Postgres `Cluster` **Healthy**, Redis pod up, API **Synced**
- `kubectl -n portfolio get ingress,svc,pods`

## 5. Image pull

If GHCR packages are **private**, configure pull secrets or `imagePullSecrets` on the API `ServiceAccount` (IRSA / dockerconfig).

## Chicken-and-egg

The **root** Application is applied **once** by Actions or admin; Argo then owns all child Applications.

Terraform creates the **cluster and LB controller**; Argo owns **applications** under `deploy/gitops/`.
