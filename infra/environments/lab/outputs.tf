output "vpc_id" {
  description = "ID of the custom Group 8 VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the ALB and NAT Gateway."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private application subnet IDs used by ECS Fargate tasks."
  value       = module.network.private_subnet_ids
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = module.network.public_route_table_id
}

output "private_route_table_id" {
  description = "ID of the private route table."
  value       = module.network.private_route_table_id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = module.network.internet_gateway_id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway."
  value       = module.network.nat_gateway_id
}

output "nat_eip_public_ip" {
  description = "Elastic IP used by the NAT Gateway."
  value       = module.network.nat_eip_public_ip
}

output "aws_account_id" {
  description = "AWS account used by the lab environment."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region used by the lab environment."
  value       = data.aws_region.current.region
}

output "ecs_cluster_id" {
  description = "ID of the Group 8 ECS cluster."
  value       = module.ecs_platform.cluster_id
}

output "ecs_cluster_arn" {
  description = "ARN of the Group 8 ECS cluster."
  value       = module.ecs_platform.cluster_arn
}

output "ecs_cluster_name" {
  description = "Name of the Group 8 ECS cluster."
  value       = module.ecs_platform.cluster_name
}

output "service_connect_namespace_arn" {
  description = "ARN of the Group 8 Service Connect namespace."
  value       = module.ecs_platform.service_connect_namespace_arn
}

output "service_connect_namespace_name" {
  description = "Name of the Group 8 Service Connect namespace."
  value       = module.ecs_platform.service_connect_namespace_name
}

output "ecs_exec_log_group_name" {
  description = "CloudWatch log group used for ECS Exec sessions."
  value       = module.ecs_platform.ecs_exec_log_group_name
}

output "execution_role_arn" {
  description = "ARN of the shared ECS task execution role."
  value       = module.iam.execution_role_arn
}

output "booking_task_role_arn" {
  description = "ARN of the Booking service task role."
  value       = module.iam.booking_task_role_arn
}

output "driver_task_role_arn" {
  description = "ARN of the Driver service task role."
  value       = module.iam.driver_task_role_arn
}

output "tracking_task_role_arn" {
  description = "ARN of the Tracking service task role."
  value       = module.iam.tracking_task_role_arn
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes via OIDC to push images to ECR."
  value       = module.iam.github_actions_role_arn
}

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer."
  value       = module.alb.alb_dns_name
}

output "booking_target_group_arn" {
  description = "ARN of the Booking target group."
  value       = module.alb.booking_target_group_arn
}

output "alb_security_group_id" {
  description = "ID of the ALB security group."
  value       = module.security.alb_security_group_id
}

output "booking_security_group_id" {
  description = "ID of the Booking service security group."
  value       = module.security.booking_security_group_id
}

output "driver_security_group_id" {
  description = "ID of the Driver service security group."
  value       = module.security.driver_security_group_id
}

output "tracking_security_group_id" {
  description = "ID of the Tracking service security group."
  value       = module.security.tracking_security_group_id
}

output "ecr_repository_urls" {
  description = "Map of service names to ECR repository URLs."
  value       = module.workloads.ecr_repository_urls
}

output "service_log_group_names" {
  description = "Map of service names to CloudWatch log group names."
  value       = module.workloads.log_group_names
}

output "booking_table_name" {
  description = "Name of the Booking pending-rides DynamoDB table."
  value       = module.workloads.booking_table_name
}

output "booking_table_arn" {
  description = "ARN of the Booking pending-rides DynamoDB table."
  value       = module.workloads.booking_table_arn
}

output "driver_service_arn" {
  description = "ARN of the Driver ECS service."
  value       = module.driver_service.service_arn
}

output "driver_task_definition_arn" {
  description = "ARN of the Driver task definition."
  value       = module.driver_service.task_definition_arn
}

output "driver_service_name" {
  description = "Name of the Driver ECS service."
  value       = module.driver_service.service_name
}

output "tracking_service_arn" {
  description = "ARN of the Tracking ECS service."
  value       = module.tracking_service.service_arn
}

output "tracking_task_definition_arn" {
  description = "ARN of the Tracking task definition."
  value       = module.tracking_service.task_definition_arn
}

output "tracking_service_name" {
  description = "Name of the Tracking ECS service."
  value       = module.tracking_service.service_name
}

output "booking_service_arn" {
  description = "ARN of the Booking ECS service."
  value       = module.booking_service.service_arn
}

output "booking_task_definition_arn" {
  description = "ARN of the Booking task definition."
  value       = module.booking_service.task_definition_arn
}

output "booking_service_name" {
  description = "Name of the Booking ECS service."
  value       = module.booking_service.service_name
}
