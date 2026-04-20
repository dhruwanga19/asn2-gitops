resource "aws_ecr_repository" "asn2_game" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "IMMUTABLE" # prevents "latest" drift; CI pushes sha-<sha> tags

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep the repo small — delete untagged images after 7 days, retain the
# most recent 20 semver-like tags.
resource "aws_ecr_lifecycle_policy" "asn2_game" {
  repository = aws_ecr_repository.asn2_game.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 20 sha- tags"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}
