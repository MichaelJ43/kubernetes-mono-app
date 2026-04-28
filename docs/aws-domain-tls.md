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

**Kustomize:** replace `REPLACE_ACM_CERTIFICATE_ARN` in `deploy/base/api/ingress.yaml`, or use `deploy/overlays/aws-prod/` and edit `ingress-acm-patch.yaml`.

## 4. Troubleshooting

| Symptom | Check |
|---------|--------|
| Certificate not provisioning | Validation CNAMEs in correct zone; no stale records at Cloudflare for same name |
| 503 from ALB | Target group health; Security groups; Pods `Ready`; `target-type: ip` matches IP mode |
| Wrong cert / TLS error | ACM cert in **same region** as ALB; Ingress annotation ARN matches |

## Renewal

ACM renews public certs automatically before expiry.
