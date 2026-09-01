data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

############################################
# Shared ECS task execution role
############################################

resource "aws_iam_role" "execution" {
  name               = var.execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = var.execution_role_name
    }
  )
}

resource "aws_iam_role_policy_attachment" "execution_managed_policy" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

############################################
# Separate task roles for least privilege
############################################

resource "aws_iam_role" "booking_task" {
  name               = var.booking_task_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(
    var.tags,
    {
      Name  = var.booking_task_role_name
      Owner = "booking-service-owner"
    }
  )
}

resource "aws_iam_role" "driver_task" {
  name               = var.driver_task_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(
    var.tags,
    {
      Name  = var.driver_task_role_name
      Owner = "driver-service-owner"
    }
  )
}

resource "aws_iam_role" "tracking_task" {
  name               = var.tracking_task_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(
    var.tags,
    {
      Name  = var.tracking_task_role_name
      Owner = "tracking-service-owner"
    }
  )
}

############################################
# ECS Exec permissions
############################################

data "aws_iam_policy_document" "ecs_exec" {
  statement {
    sid    = "ECSExecSessionChannels"
    effect = "Allow"

    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ECSExecCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      var.ecs_exec_log_group_arn,
      "${var.ecs_exec_log_group_arn}:*"
    ]
  }
}

resource "aws_iam_policy" "ecs_exec" {
  name        = "${var.name_prefix}-ecs-exec-policy"
  description = "Allows Group 8 ECS tasks to establish ECS Exec sessions and write session logs."
  policy      = data.aws_iam_policy_document.ecs_exec.json

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-ecs-exec-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "booking_ecs_exec" {
  role       = aws_iam_role.booking_task.name
  policy_arn = aws_iam_policy.ecs_exec.arn
}

resource "aws_iam_role_policy_attachment" "driver_ecs_exec" {
  role       = aws_iam_role.driver_task.name
  policy_arn = aws_iam_policy.ecs_exec.arn
}

resource "aws_iam_role_policy_attachment" "tracking_ecs_exec" {
  role       = aws_iam_role.tracking_task.name
  policy_arn = aws_iam_policy.ecs_exec.arn
}

############################################
# Booking-only DynamoDB permissions
############################################

data "aws_iam_policy_document" "booking_dynamodb" {
  statement {
    sid    = "BookingPendingRidesTableAccess"
    effect = "Allow"

    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem"
    ]

    resources = [
      var.booking_dynamodb_table_arn
    ]
  }
}

resource "aws_iam_policy" "booking_dynamodb" {
  name        = "${var.name_prefix}-booking-dynamodb-policy"
  description = "Allows only Booking service to use the pending-rides DynamoDB table."
  policy      = data.aws_iam_policy_document.booking_dynamodb.json

  tags = merge(
    var.tags,
    {
      Name  = "${var.name_prefix}-booking-dynamodb-policy"
      Owner = "booking-service-owner"
    }
  )
}

resource "aws_iam_role_policy_attachment" "booking_dynamodb" {
  role       = aws_iam_role.booking_task.name
  policy_arn = aws_iam_policy.booking_dynamodb.arn
}

############################################
# GitHub Actions CI/CD role (OIDC, no static keys)
############################################

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.github_actions_role_name
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = var.github_actions_role_name
    }
  )
}

data "aws_iam_policy_document" "github_actions_ecr_push" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushGroup8Repositories"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]

    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_policy" "github_actions_ecr_push" {
  name        = "${var.name_prefix}-github-actions-ecr-push-policy"
  description = "Allows GitHub Actions to push Group 8 service images to ECR."
  policy      = data.aws_iam_policy_document.github_actions_ecr_push.json

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-github-actions-ecr-push-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr_push.arn
}
