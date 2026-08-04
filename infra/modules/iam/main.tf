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
