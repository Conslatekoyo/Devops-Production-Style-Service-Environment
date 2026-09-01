data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "artifacts" {
  bucket = var.artifact_bucket_name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-codepipeline-artifacts"
  })
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codebuild" {
  name = "${var.name_prefix}-codebuild-role"

  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.name_prefix}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "*"
      },
      {
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },
      {
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]

        Resource = [
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${var.name_prefix}-booking-service",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${var.name_prefix}-driver-service",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${var.name_prefix}-tracking-service"
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]

        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Effect = "Allow"

        Action = [
          "s3:GetBucketVersioning"
        ]

        Resource = aws_s3_bucket.artifacts.arn
      }
    ]
  })
}

resource "aws_iam_role" "codepipeline" {
  name = "${var.name_prefix}-codepipeline-role"

  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.name_prefix}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ]

        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]

        Resource = [
          aws_codebuild_project.booking.arn,
          aws_codebuild_project.driver.arn,
          aws_codebuild_project.tracking.arn
        ]
      },
	{
  	Effect = "Allow"
  	Action = [
    	"codeconnections:UseConnection"
  	]
  	Resource = var.connection_arn
	},
      {
        Effect = "Allow"

        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService"
        ]

        Resource = "*"
      },
      {
        Effect = "Allow"

        Action = [
          "iam:PassRole"
        ]

        Resource = [
          "arn:aws:iam::${var.aws_account_id}:role/${var.name_prefix}-ecs-execution-role",
          "arn:aws:iam::${var.aws_account_id}:role/${var.name_prefix}-booking-task-role",
          "arn:aws:iam::${var.aws_account_id}:role/${var.name_prefix}-driver-task-role",
          "arn:aws:iam::${var.aws_account_id}:role/${var.name_prefix}-tracking-task-role"
        ]
      }
    ]
  })
}

resource "aws_codebuild_project" "booking" {
  name         = "${var.name_prefix}-booking-service-build"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/booking-service.yml"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.aws_account_id
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${var.name_prefix}-booking-service"
      stream_name = "build"
    }
  }

  tags = var.tags
}

resource "aws_codebuild_project" "driver" {
  name         = "${var.name_prefix}-driver-service-build"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/driver-buildspec.yml"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.aws_account_id
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${var.name_prefix}-driver-service"
      stream_name = "build"
    }
  }

  tags = var.tags
}

resource "aws_codebuild_project" "tracking" {
  name         = "${var.name_prefix}-tracking-service-build"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/tracking-service.yml"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.aws_account_id
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${var.name_prefix}-tracking-service"
      stream_name = "build"
    }
  }

  tags = var.tags
}

locals {
  pipelines = {
    booking = {
      name             = "${var.name_prefix}-booking-service-pipeline"
      build_project    = aws_codebuild_project.booking.name
      service_name     = var.booking_service_name
      buildspec        = "buildspecs/booking-service.yml"
    }

    driver = {
      name             = "${var.name_prefix}-driver-service-pipeline"
      build_project    = aws_codebuild_project.driver.name
      service_name     = var.driver_service_name
      buildspec        = "buildspecs/driver-buildspec.yml"
    }

    tracking = {
      name             = "${var.name_prefix}-tracking-service-pipeline"
      build_project    = aws_codebuild_project.tracking.name
      service_name     = var.tracking_service_name
      buildspec        = "buildspecs/tracking-service.yml"
    }
  }
}

resource "aws_codepipeline" "service" {
  for_each = local.pipelines

  name     = each.value.name
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        ConnectionArn    = var.connection_arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"

      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]

      configuration = {
        ProjectName = each.value.build_project
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployToECS"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["BuildOutput"]

      configuration = {
        ClusterName = var.cluster_name
        ServiceName = each.value.service_name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  tags = var.tags
}
