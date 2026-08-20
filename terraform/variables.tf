variable "aws_region" {
  description = "AWS Region used for the project"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name used to identify project resources"
  type        = string
  default     = "techpathway-capstone"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block assigned to the project VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks assigned to public subnets"
  type        = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks assigned to private subnets"
  type        = list(string)
  default = [
    "10.0.3.0/24",
    "10.0.4.0/24"
  ]
}

variable "cluster_name" {
  description = "Name assigned to the Amazon EKS cluster"
  type        = string
  default     = "techpathway-eks-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version used by Amazon EKS"
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "EC2 instance types used by the managed node group"
  type        = list(string)
  default     = ["c7i-flex.large"]
}

variable "node_desired_size" {
  description = "Initial number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 4
}

variable "ecr_repository_names" {
  description = "Names of the private ECR repositories"
  type        = set(string)

  default = [
    "action-messages",
    "techpathway-warehouse",
    "weekly-call"
  ]
}