variable "name_prefix" {
  type        = string
  description = "Prefix applied to Group 8 IAM resources."
  default     = "devops-g8"

  validation {
    condition     = startswith(var.name_prefix, "devops-g8")
    error_message = "name_prefix must begin with devops-g8."
  }
}

variable "execution_role_name" {
  type        = string
  description = "Name of the shared ECS task execution role."
  default     = "devops-g8-ecs-execution-role"
}

variable "booking_task_role_name" {
  type        = string
  description = "Name of the Booking service task role."
  default     = "devops-g8-booking-task-role"
}

variable "driver_task_role_name" {
  type        = string
  description = "Name of the Driver service task role."
  default     = "devops-g8-driver-task-role"
}

variable "tracking_task_role_name" {
  type        = string
  description = "Name of the Tracking service task role."
  default     = "devops-g8-tracking-task-role"
}

variable "ecs_exec_log_group_arn" {
  type        = string
  description = "ARN of the CloudWatch log group used for ECS Exec session logging."

  validation {
    condition     = can(regex("^arn:aws:logs:", var.ecs_exec_log_group_arn))
    error_message = "ecs_exec_log_group_arn must be a valid CloudWatch Logs ARN."
  }
}

variable "github_repository" {
  type        = string
  description = "GitHub repository authorized to assume the CI/CD role, as \"owner/repo\"."

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository must be in the form \"owner/repo\"."
  }
}

variable "github_actions_role_name" {
  type        = string
  description = "Name of the IAM role assumed by GitHub Actions to publish images to ECR."
  default     = "devops-g8-github-actions-role"
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "ARNs of the Group 8 ECR repositories GitHub Actions is allowed to push to."
}

variable "booking_dynamodb_table_arn" {
  type        = string
  description = "ARN of the DynamoDB pending-rides table used only by Booking."
  default     = null
  nullable    = true

  validation {
    condition = (
      var.booking_dynamodb_table_arn == null ||
      can(regex("^arn:aws:dynamodb:", var.booking_dynamodb_table_arn))
    )

    error_message = "booking_dynamodb_table_arn must be null or a valid DynamoDB table ARN."
  }
}

variable "tags" {
  type        = map(string)
  description = "Required tags applied to Group 8 IAM resources."

  default = {
    Project     = "devops-mentorship"
    Group       = "group-8"
    Environment = "lab"
    ManagedBy   = "Terraform"
    Owner       = "platform-owner"
  }

  validation {
    condition = alltrue([
      contains(keys(var.tags), "Project"),
      contains(keys(var.tags), "Group"),
      contains(keys(var.tags), "Environment"),
      contains(keys(var.tags), "ManagedBy"),
      contains(keys(var.tags), "Owner")
    ])

    error_message = "tags must include Project, Group, Environment, ManagedBy and Owner."
  }
}
