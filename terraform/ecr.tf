# -----------------------------------------------------------------------------
# Amazon Elastic Container Registry
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "applications" {
  for_each = var.ecr_repository_names

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = each.value
    Application = each.value
  }
}

# -----------------------------------------------------------------------------
# ECR Lifecycle Policies
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "applications" {
  for_each = aws_ecr_repository.applications

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the most recent 10 images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}