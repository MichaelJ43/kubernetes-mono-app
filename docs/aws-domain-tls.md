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

### Terraform: ExternalDNS → Route 53 (recommended)

If your **public hosted zone** for `k8s.michaelj43.dev` lives in **Route 53** (with NS delegation from Cloudflare, etc.):

1. Copy the hosted **zone ID** from Route 53 (e.g. `Z0…`).
2. Set repository **Variable** **`EXTERNAL_DNS_ZONE_ID`** to that ID (or pass `external_dns_route53_zone_id` when applying **`k8s_platform`** locally—see [`infra/aws/examples/k8s_platform/terraform.tfvars.example`](../infra/aws/examples/k8s_platform/terraform.tfvars.example)).
3. Run **`terraform apply`** on **`k8s_platform`** (or merge a change under `infra/aws/` so GitHub Actions applies). Terraform installs **[ExternalDNS](https://github.com/kubernetes-sigs/external-dns)** with **IRSA**; it watches **Ingress** resources and creates **alias** records (and ownership TXT records) in that zone for hostnames such as **`api.k8s.michaelj43.dev`** once the AWS Load Balancer Controller has published the ALB address on the Ingress.
4. **Apply foundation at least once** after updating the repo so remote state includes **`oidc_provider_arn`** (required for the ExternalDNS IRSA role).

After Argo has synced the API Ingress, allow a short interval for ExternalDNS to reconcile (chart default loop ~1m).

**Manual alternative (no ExternalDNS):** create an **alias** (or CNAME) record `api.k8s.michaelj43.dev` → the ALB DNS name from `kubectl -n portfolio get ingress api`.

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
| **api…** does not resolve | **`EXTERNAL_DNS_ZONE_ID`** set and **k8s_platform** applied; Ingress has ALB hostname in status; `kubectl -n kube-system logs deploy/external-dns` |

## Renewal

ACM renews public certs automatically before expiry.
