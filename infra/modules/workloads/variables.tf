variable "name_prefix" {
  type        = string
  description = "Prefix applied to Group 8 workload resources."
  default     = "devops-g8"

  validation {
    condition     = startswith(var.name_prefix, "devops-g8")
    error_message = "name_prefix must begin with devops-g8."
  }
}

variable "service_names" {
  type        = set(string)
  description = "Names of the three Group 8 application services."

  default = [
    "booking-service",
    "driver-service",
    "tracking-service"
  ]

  validation {
    condition = var.service_names == toset([
      "booking-service",
      "driver-service",
      "tracking-service"
    ])

    error_message = "service_names must contain booking-service, driver-service and tracking-service."
  }
}

variable "ecr_image_tag_mutability" {
  type        = string
  description = "ECR tag mutability setting."
  default     = "IMMUTABLE"

  validation {
    condition     = var.ecr_image_tag_mutability == "IMMUTABLE"
    error_message = "ECR image tags must remain immutable."
  }
}

variable "enable_ecr_scan_on_push" {
  type        = bool
  description = "Enable image scanning whenever an image is pushed to ECR."
  default     = true

  validation {
    condition     = var.enable_ecr_scan_on_push
    error_message = "ECR scan-on-push must remain enabled."
  }
}

variable "ecr_untagged_image_retention" {
  type        = number
  description = "Number of recent untagged ECR images retained per repository."
  default     = 5

  validation {
    condition     = var.ecr_untagged_image_retention >= 1
    error_message = "At least one recent untagged image must be retained."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Retention period for Booking, Driver and Tracking CloudWatch logs."
  default     = 14

  validation {
    condition     = contains([7, 14, 30, 60, 90], var.log_retention_days)
    error_message = "log_retention_days must be one of 7, 14, 30, 60 or 90."
  }
}

variable "booking_table_name" {
  type        = string
  description = "DynamoDB table used by Booking to store pending ride state."
  default     = "devops-g8-pending-rides"

  validation {
    condition     = startswith(var.booking_table_name, "devops-g8-")
    error_message = "booking_table_name must begin with devops-g8-."
  }
}

variable "booking_table_partition_key" {
  type        = string
  description = "Partition key used by the Booking pending-rides table."
  default     = "ride_id"

  validation {
    condition     = var.booking_table_partition_key == "ride_id"
    error_message = "The Booking pending-rides table must use ride_id as its partition key."
  }
}

variable "tags" {
  type        = map(string)
  description = "Required tags applied to Group 8 workload resources."

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
