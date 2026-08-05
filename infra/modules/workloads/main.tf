############################################
# ECR repositories
############################################

resource "aws_ecr_repository" "service" {
  for_each = var.service_names

  name                 = "${var.name_prefix}-${each.value}"
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.enable_ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.name_prefix}-${each.value}"
      Service = each.value
    }
  )
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain only the configured number of untagged images."
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_untagged_image_retention
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

############################################
# CloudWatch service log groups
############################################

resource "aws_cloudwatch_log_group" "service" {
  for_each = var.service_names

  name              = "/ecs/${var.name_prefix}-${each.value}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name    = "/ecs/${var.name_prefix}-${each.value}"
      Service = each.value
    }
  )
}

############################################
# Booking pending-rides DynamoDB table
############################################

resource "aws_dynamodb_table" "booking_pending_rides" {
  name         = var.booking_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.booking_table_partition_key

  attribute {
    name = var.booking_table_partition_key
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(
    var.tags,
    {
      Name  = var.booking_table_name
      Owner = "booking-service-owner"
    }
  )
}
