variable "name_prefix" {
  type        = string
  description = "Prefix applied to all Group 8 network resources."
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

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Two Availability Zones used by the public and private subnets."
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

    error_message = "Exactly two distinct Availability Zones from eu-west-3 must be provided."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for the two public subnets."
  default     = ["10.8.0.0/24", "10.8.1.0/24"]

  validation {
    condition = (
      length(var.public_subnet_cidrs) == 2 &&
      length(distinct(var.public_subnet_cidrs)) == 2 &&
      alltrue([
        for cidr in var.public_subnet_cidrs :
        can(cidrnetmask(cidr))
      ])
    )

    error_message = "Exactly two distinct valid public subnet CIDRs must be provided."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for the two private application subnets."
  default     = ["10.8.10.0/24", "10.8.11.0/24"]

  validation {
    condition = (
      length(var.private_subnet_cidrs) == 2 &&
      length(distinct(var.private_subnet_cidrs)) == 2 &&
      alltrue([
        for cidr in var.private_subnet_cidrs :
        can(cidrnetmask(cidr))
      ])
    )

    error_message = "Exactly two distinct valid private subnet CIDRs must be provided."
  }
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Whether to create one NAT Gateway for private-subnet outbound access."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Required tags applied to all network resources."

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
