variable "aws_region" {
  type        = string
  description = "AWS Region assigned to Group 8."
  default     = "eu-west-3"

  validation {
    condition     = var.aws_region == "eu-west-3"
    error_message = "Group 8 infrastructure must be deployed only in eu-west-3."
  }
}

variable "aws_account_id" {
  type        = string
  description = "Authorized classroom AWS account ID."
  default     = "827478161993"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a valid 12-digit AWS account ID."
  }
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for Terraform workload state."
}

variable "lock_table_name" {
  type        = string
  description = "DynamoDB table used for Terraform state locking."
  default     = "devops-g8-tf-lock"
}

variable "tags" {
  type        = map(string)
  description = "Required tags applied to bootstrap resources."

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
