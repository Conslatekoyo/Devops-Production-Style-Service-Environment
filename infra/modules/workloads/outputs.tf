output "ecr_repository_urls" {
  description = "Map of service names to ECR repository URLs."
  value = {
    for service_name, repository in aws_ecr_repository.service :
    service_name => repository.repository_url
  }
}

output "ecr_repository_arns" {
  description = "Map of service names to ECR repository ARNs."
  value = {
    for service_name, repository in aws_ecr_repository.service :
    service_name => repository.arn
  }
}

output "log_group_names" {
  description = "Map of service names to CloudWatch log group names."
  value = {
    for service_name, log_group in aws_cloudwatch_log_group.service :
    service_name => log_group.name
  }
}

output "log_group_arns" {
  description = "Map of service names to CloudWatch log group ARNs."
  value = {
    for service_name, log_group in aws_cloudwatch_log_group.service :
    service_name => log_group.arn
  }
}

output "booking_table_name" {
  description = "Name of the Booking pending-rides DynamoDB table."
  value       = aws_dynamodb_table.booking_pending_rides.name
}

output "booking_table_arn" {
  description = "ARN of the Booking pending-rides DynamoDB table."
  value       = aws_dynamodb_table.booking_pending_rides.arn
}
