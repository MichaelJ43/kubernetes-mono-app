# AWS: domain, Route 53, ACM, ALB

This project uses **`k8s.michaelj43.dev`** as the delegated zone for Kubernetes services, with TLS via **ACM** on the **ALB** (no cert-manager).

## 1. Delegate `k8s.michaelj43.dev` to Route 53

1. In Route 53, create a **public hosted zone** `k8s.michaelj43.dev`.
2. Note the four **NS** records AWS assigns.
3. In **Cloudflare** (apex `michaelj43.dev`), create an **NS** delegation for hostname `k8s` pointing to those four nameservers only.
4. Do **not** create conflicting A/CNAME records for the same names in Cloudflare once delegation is live—Route 53 owns the zone.

Wait for DNS propagation before ACM validation.

## 2. ACM certificate

1. In **ACM** (same **region** as your EKS / ALB), request a public certificate with:
   - `k8s.michaelj43.dev`
   - `*.k8s.michaelj43.dev`
2. Validate with **DNS**: add the CNAME records ACM gives you **in the Route 53 zone** `k8s.michaelj43.dev`.

The single-label wildcard covers hostnames like `api.k8s.michaelj43.dev` but **not** `api.foo.k8s.michaelj43.dev`.

## 3. ALB Ingress

1. Install **AWS Load Balancer Controller** on the cluster (IAM policy + Helm chart—see AWS docs).
2. Annotate the API Ingress with:
   - `alb.ingress.kubernetes.io/certificate-arn` → your ACM cert ARN
   - `alb.ingress.kubernetes.io/scheme: internet-facing`
   - `alb.ingress.kubernetes.io/target-type: ip`
3. In **Route 53**, create an **alias** (or CNAME) record `api.k8s.michaelj43.dev` → the ALB DNS name emitted by the controller.

**Kustomize / Argo:** the **`api`** Argo app should sync **`deploy/overlays/aws-prod`**, which patches **`deploy/base/api`**. Set the ACM ARN in **`deploy/overlays/aws-prod/ingress-acm-patch.yaml`**.

For **ad-hoc** apply without the overlay, you can set `REPLACE_ACM_CERTIFICATE_ARN` in `deploy/base/api/ingress.yaml` instead.

## 4. Programmatic ARN (Terraform + script)

**Argo CD reads manifests from Git**, not from GitHub Secrets—there is no built-in way to “inject” an ACM ARN from a repository secret into an Ingress annotation during sync. Typical patterns:

| Approach | Notes |
|----------|--------|
| **Terraform output** | In `infra/aws/foundation`, set optional variable **`acm_certificate_domain`** to your cert’s **Domain name** in ACM (e.g. `*.k8s.michaelj43.dev`), same region as `aws_region`. After `terraform apply`, run **`terraform output acm_certificate_arn`**. |
| **Helper script** | From repo root: **`./scripts/render-ingress-acm-patch.sh`** reads that output (or **`ACM_CERTIFICATE_ARN`**, or **`--from-aws REGION DOMAIN`** with AWS CLI + `jq`) and writes `deploy/overlays/aws-prod/ingress-acm-patch.yaml`. Commit and push so Argo picks it up. |
| **GitHub Actions (advanced)** | A workflow could assume OIDC, call `aws acm list-certificates`, and open a PR that updates the patch file (not included by default). |

## 5. Troubleshooting

| Symptom | Check |
|---------|--------|
| Certificate not provisioning | Validation CNAMEs in correct zone; no stale records at Cloudflare for same name |
| 503 from ALB | Target group health; Security groups; Pods `Ready`; `target-type: ip` matches IP mode |
| Wrong cert / TLS error | ACM cert in **same region** as ALB; Ingress annotation ARN matches |

## Renewal

ACM renews public certs automatically before expiry.
