# Runbook: Teardown

**Warning:** This destroys **Argo CD** in the target cluster context. It does **not** automatically delete workload namespaces such as `portfolio`, PVCs, or the EKS cluster.

## Steps

1. Run GitHub workflow **Argo CD teardown** with `confirm` = `DELETE`, plus cluster name and region.
2. Or manually:
   ```bash
   kubectl delete -f deploy/gitops/root-app.yaml
   helm uninstall argocd -n argocd
   ```

## What remains

- **Namespaces** `portfolio`, `cnpg-system`, etc., until you delete them.
- **EBS volumes** bound to PVCs may incur cost until volumes are released.
- **Route 53 / ACM** resources in AWS are untouched.

## Data loss

Assume **all in-cluster Postgres / Redis data is lost** when deleting namespaces or recycling PVCs. Document backups separately if you need retention.
