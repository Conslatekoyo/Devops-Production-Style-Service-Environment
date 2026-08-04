provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
