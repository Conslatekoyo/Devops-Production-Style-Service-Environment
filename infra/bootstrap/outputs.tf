output "state_bucket_name" {
  description = "Name of the S3 bucket storing Terraform workload state."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket storing Terraform workload state."
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.terraform_lock.name
}

output "aws_account_id" {
  description = "AWS account where the backend was created."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where the backend was created."
  value       = data.aws_region.current.region
}
