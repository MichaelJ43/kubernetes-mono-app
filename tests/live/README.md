# Live / in-cluster checks

After GitOps sync, validate the stack with:

- `kubectl -n portfolio rollout status deploy/api`
- `kubectl -n portfolio run curl --rm -it --restart=Never --image=curlimages/curl -- curl -sf http://api.portfolio.svc/items`

For testing through the real ALB + TLS hostname, run a **post-deploy** workflow (or `workflow_dispatch`) that curls `https://api.k8s.michaelj43.dev/health` with retries—document timeouts in this repo when you add that job.
