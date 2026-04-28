output "aws_load_balancer_controller_release" {
  value       = helm_release.aws_load_balancer_controller.name
  description = "Helm release name for AWS Load Balancer Controller"
}
