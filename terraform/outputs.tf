output "aws_account_id" {
  description = "AWS account ID used by Terraform"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region used by Terraform"
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID of the project VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "Availability Zones used by the project"
  value = [
    for subnet in aws_subnet.public : subnet.availability_zone
  ]
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "ecr_repository_urls" {
  description = "URLs of the private ECR repositories"

  value = {
    for name, repository in aws_ecr_repository.applications :
    name => repository.repository_url
  }
}

output "eks_cluster_role_arn" {
  description = "ARN of the EKS control plane IAM role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS managed node group IAM role"
  value       = aws_iam_role.eks_nodes.arn
}

output "eks_cluster_name" {
  description = "Name of the Amazon EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "API endpoint of the Amazon EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "eks_node_group_name" {
  description = "Name of the EKS managed node group"
  value       = aws_eks_node_group.main.node_group_name
}

output "eks_oidc_provider_arn" {
  description = "ARN of the EKS OpenID Connect provider"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "configure_kubectl_command" {
  description = "Command used to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}