variable "name_prefix" {
  type        = string
  description = "Prefix applied to Group 8 security-group resources."
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

variable "alb_port" {
  type        = number
  description = "Public HTTP port exposed by the Application Load Balancer."
  default     = 80

  validation {
    condition     = var.alb_port == 80
    error_message = "The ALB must expose port 80 for this lab."
  }
}

variable "booking_port" {
  type        = number
  description = "Booking service application port."
  default     = 3001

  validation {
    condition     = var.booking_port == 3001
    error_message = "Booking service must use port 3001."
  }
}

variable "driver_port" {
  type        = number
  description = "Driver service application port."
  default     = 3002

  validation {
    condition     = var.driver_port == 3002
    error_message = "Driver service must use port 3002."
  }
}

variable "tracking_port" {
  type        = number
  description = "Tracking service application port."
  default     = 3003

  validation {
    condition     = var.tracking_port == 3003
    error_message = "Tracking service must use port 3003."
  }
}

variable "allow_tracking_callback_to_booking" {
  type        = bool
  description = "Allow the approved Tracking-to-Booking confirmation callback."
  default     = true

  validation {
    condition     = var.allow_tracking_callback_to_booking
    error_message = "The current Group 8 application requires the Tracking-to-Booking callback."
  }
}

variable "tags" {
  type        = map(string)
  description = "Required tags applied to Group 8 security resources."

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
