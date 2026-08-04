variable "name_prefix" {
  type        = string
  description = "Prefix applied to Group 8 ALB resources."
  default     = "devops-g8"

  validation {
    condition     = startswith(var.name_prefix, "devops-g8")
    error_message = "name_prefix must begin with devops-g8."
  }
}

variable "vpc_id" {
  type        = string
  description = "ID of the custom Group 8 VPC."

  validation {
    condition     = startswith(var.vpc_id, "vpc-")
    error_message = "vpc_id must be a valid VPC ID."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Two public subnet IDs used by the internet-facing ALB."

  validation {
    condition = (
      length(var.public_subnet_ids) >= 2 &&
      length(distinct(var.public_subnet_ids)) >= 2
    )

    error_message = "The ALB must span at least two distinct public subnets."
  }
}

variable "alb_security_group_id" {
  type        = string
  description = "Security group attached to the ALB."

  validation {
    condition     = startswith(var.alb_security_group_id, "sg-")
    error_message = "alb_security_group_id must be a valid security group ID."
  }
}

variable "booking_port" {
  type        = number
  description = "Booking service application port used by the target group."
  default     = 3001

  validation {
    condition     = var.booking_port == 3001
    error_message = "Booking service must use port 3001."
  }
}

variable "health_check_path" {
  type        = string
  description = "Health-check path used by the Booking target group."
  default     = "/health"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must begin with /."
  }
}

variable "target_type" {
  type        = string
  description = "Target group target type."
  default     = "ip"

  validation {
    condition     = var.target_type == "ip"
    error_message = "The ECS Fargate target group must use target_type = ip."
  }
}

variable "tags" {
  type        = map(string)
  description = "Required tags applied to ALB resources."

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
