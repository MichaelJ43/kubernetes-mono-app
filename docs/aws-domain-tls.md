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

## 3. ALB Ingress (no ACM ARN in Git — certificate discovery)

The **AWS Load Balancer Controller** can attach ACM certificates **automatically** when you **omit** `alb.ingress.kubernetes.io/certificate-arn` but:

- Declare **HTTPS** with `alb.ingress.kubernetes.io/listen-ports` (already set in `deploy/base/api/ingress.yaml`), and
- Put the hostname in **`spec.tls.hosts`** and/or **`spec.rules[].host`** (both are set for `api.k8s.michaelj43.dev`).

Then, in the **same AWS account and region** as the ALB, any **ISSUED** ACM certificate that matches that hostname (including a wildcard `*.k8s.michaelj43.dev`) can be discovered—**no ARN is stored in the public repository**.

Details: [Certificate discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/cert_discovery/).

**Manual steps:**

1. Install **AWS Load Balancer Controller** on the cluster (`k8s_platform` Terraform stack).
2. Ensure the API **Ingress** in Git matches your real DNS name (or fork and change the host + `spec.tls.hosts`).
3. In **Route 53**, create an **alias** (or CNAME) record `api.k8s.michaelj43.dev` → the ALB DNS name (`kubectl -n portfolio get ingress api`).

**Argo:** the **`api`** app syncs **`deploy/base/api`**. Optional **`deploy/overlays/aws-prod`** wraps the same base without adding ACM annotations.

### Optional: explicit `certificate-arn` (private repo / debugging)

If you **must** pin an ARN (e.g. multiple ambiguous certs), add annotation `alb.ingress.kubernetes.io/certificate-arn` via a local-only overlay or a **private** config repo—**do not commit real ARNs to a public GitHub repo.**

## 4. Terraform: optional ACM output (accounting / docs only)

In `infra/aws/foundation`, optional variable **`acm_certificate_domain`** (e.g. `*.k8s.michaelj43.dev`) exposes output **`acm_certificate_arn`** after `terraform apply`. Useful for logging or **private** automation; it is **not required** for Argo when using certificate discovery.

**Argo CD does not read GitHub Secrets** for Ingress annotations. To “hide” the ARN, use **discovery** (above) or keep manifests in a **private** repository.

## 5. Troubleshooting

| Symptom | Check |
|---------|--------|
| Certificate not provisioning | Validation CNAMEs in correct zone; no stale records at Cloudflare for same name |
| 503 from ALB | Target group health; Security groups; Pods `Ready`; `target-type: ip` matches IP mode |
| Wrong cert / TLS error | ACM cert in **same region** as ALB; hostname in Ingress matches cert SANs; only one good match or use explicit ARN in a non-public path |
| Discovery finds no cert | `spec.tls.hosts` / rule `host` aligned with ACM; cert **ISSUED** in same account/region |

## Renewal

ACM renews public certs automatically before expiry.
