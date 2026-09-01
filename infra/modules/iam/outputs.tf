output "execution_role_name" {
  description = "Name of the shared ECS task execution role."
  value       = aws_iam_role.execution.name
}

output "execution_role_arn" {
  description = "ARN of the shared ECS task execution role."
  value       = aws_iam_role.execution.arn
}

output "booking_task_role_name" {
  description = "Name of the Booking service task role."
  value       = aws_iam_role.booking_task.name
}

output "booking_task_role_arn" {
  description = "ARN of the Booking service task role."
  value       = aws_iam_role.booking_task.arn
}

output "driver_task_role_name" {
  description = "Name of the Driver service task role."
  value       = aws_iam_role.driver_task.name
}

output "driver_task_role_arn" {
  description = "ARN of the Driver service task role."
  value       = aws_iam_role.driver_task.arn
}

output "tracking_task_role_name" {
  description = "Name of the Tracking service task role."
  value       = aws_iam_role.tracking_task.name
}

output "tracking_task_role_arn" {
  description = "ARN of the Tracking service task role."
  value       = aws_iam_role.tracking_task.arn
}

output "ecs_exec_policy_arn" {
  description = "ARN of the ECS Exec policy attached to all three task roles."
  value       = aws_iam_policy.ecs_exec.arn
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes via OIDC to push images to ECR."
  value       = aws_iam_role.github_actions.arn
}
