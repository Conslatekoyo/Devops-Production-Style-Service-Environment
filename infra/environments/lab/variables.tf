variable "aws_region" {
  type        = string
  description = "AWS Region assigned to Group 8."
  default     = "eu-west-3"

  validation {
    condition     = var.aws_region == "eu-west-3"
    error_message = "Group 8 resources must be deployed only in eu-west-3."
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

variable "name_prefix" {
  type        = string
  description = "Required prefix for all Group 8 resources."
  default     = "devops-g8"

  validation {
    condition     = startswith(var.name_prefix, "devops-g8")
    error_message = "name_prefix must begin with devops-g8."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the custom Group 8 VPC."
  default     = "10.8.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability Zones used by the lab environment."
  default     = ["eu-west-3a", "eu-west-3b"]

  validation {
    condition = (
      length(var.availability_zones) == 2 &&
      length(distinct(var.availability_zones)) == 2 &&
      alltrue([
        for az in var.availability_zones :
        startswith(az, "eu-west-3")
      ])
    )

    error_message = "Exactly two distinct Availability Zones in eu-west-3 are required."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for the two public subnets."
  default     = ["10.8.0.0/24", "10.8.1.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for the two private application subnets."
  default     = ["10.8.10.0/24", "10.8.11.0/24"]
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Create the single NAT Gateway approved in the Gate 1 design."
  default     = true

  validation {
    condition     = var.enable_nat_gateway
    error_message = "The Group 8 lab design requires the NAT Gateway to remain enabled."
  }
}

variable "tags" {
  type        = map(string)
  description = "Required tags applied to managed infrastructure."

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
