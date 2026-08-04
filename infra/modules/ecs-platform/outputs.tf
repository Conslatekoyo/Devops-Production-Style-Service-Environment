output "cluster_id" {
  description = "ID of the Group 8 ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the Group 8 ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the Group 8 ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "service_connect_namespace_id" {
  description = "ID of the Group 8 Service Connect namespace."
  value       = aws_service_discovery_http_namespace.this.id
}

output "service_connect_namespace_arn" {
  description = "ARN of the Group 8 Service Connect namespace."
  value       = aws_service_discovery_http_namespace.this.arn
}

output "service_connect_namespace_name" {
  description = "Name of the Group 8 Service Connect namespace."
  value       = aws_service_discovery_http_namespace.this.name
}

output "ecs_exec_log_group_name" {
  description = "CloudWatch log group used for ECS Exec sessions."
  value       = aws_cloudwatch_log_group.ecs_exec.name
}

output "ecs_exec_log_group_arn" {
  description = "ARN of the CloudWatch log group used for ECS Exec sessions."
  value       = aws_cloudwatch_log_group.ecs_exec.arn
}
