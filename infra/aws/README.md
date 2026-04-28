# AWS foundation (optional)

This folder is reserved for Terraform, CDK, or eksctl definitions that provision **EKS**, VPC, IAM for GitHub OIDC, and the **EBS CSI** driver.

The rest of this repo assumes you already have a working EKS cluster (`kubectl` context) before running the Argo CD bootstrap workflow.

Common checklist:

- EKS control plane + node group (Kubernetes 1.29+ recommended).
- **AWS Load Balancer Controller** installed for `Ingress` + ALB.
- **EBS CSI** (or compatible storage class) if you enable Postgres persistence beyond operator defaults.

Nothing in this directory is required for local development or CI.
