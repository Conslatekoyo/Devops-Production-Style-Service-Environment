variable "name_prefix" {
  type        = string
  description = "Prefix applied to shared Group 8 ECS platform resources."
  default     = "devops-g8"

  validation {
    condition     = startswith(var.name_prefix, "devops-g8")
    error_message = "name_prefix must begin with devops-g8."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster."
  default     = "devops-g8-cluster"
}

variable "service_connect_namespace" {
  type        = string
  description = "ECS Service Connect namespace used by Booking, Driver and Tracking."
  default     = "group8.internal"

  validation {
    condition     = var.service_connect_namespace == "group8.internal"
    error_message = "The Group 8 Service Connect namespace must be group8.internal."
  }
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable CloudWatch Container Insights for the ECS cluster."
  default     = true

  validation {
    condition     = var.enable_container_insights
    error_message = "Container Insights must remain enabled for the lab."
  }
}

variable "exec_log_group_name" {
  type        = string
  description = "CloudWatch log group used for ECS Exec session logging."
  default     = "/ecs/devops-g8-exec"
}

variable "exec_log_retention_days" {
  type        = number
  description = "Retention period for ECS Exec session logs."
  default     = 14

  validation {
    condition     = contains([7, 14, 30, 60, 90], var.exec_log_retention_days)
    error_message = "exec_log_retention_days must be one of 7, 14, 30, 60 or 90."
  }
}

variable "tags" {
  type        = map(string)
  description = "Required tags applied to shared ECS platform resources."

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
