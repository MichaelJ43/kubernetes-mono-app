# Runbook: Bootstrap

**Goal:** EKS cluster exists, ALB controller installed (for Ingress), `kubectl` context works from your machine or CI.

## 1. GitHub → AWS (OIDC)

Create an IAM role trusted by GitHub OIDC (`aws-actions/configure-aws-credentials`) with policies allowing:

- `eks:DescribeCluster`, `eks:ListClusters`
- `sts:GetCallerIdentity`
- Enough access for `aws eks update-kubeconfig` and Helm installs

Store the role ARN in **`AWS_ROLE_ARN_BOOTSTRAP`** (GitHub secret).

## 2. Install Argo CD

- **CI:** run workflow **Argo CD bootstrap** (`argocd-bootstrap.yaml`) with cluster name + region.
- **Locally:**  
  ```bash
  helm repo add argo https://argoproj.github.io/argo-helm
  helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace -f infra/argocd/values.yaml
  kubectl apply -f deploy/gitops/root-app.yaml
  ```

## 3. Initial admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Port-forward UI (default: secure `ClusterIP`):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

## 4. Verify workloads

In Argo CD (or `kubectl`):

- `cnpg-system` — operator running
- `portfolio` — Postgres `Cluster` **Healthy**, Redis pod up, API **Synced**
- `kubectl -n portfolio get ingress,svc,pods`

## 5. Image pull

If GHCR packages are **private**, configure pull secrets or `imagePullSecrets` on the API `ServiceAccount` (IRSA / dockerconfig).

## Chicken-and-egg

The **root** Application is applied **once** by Actions or admin; Argo then owns all child Applications.
