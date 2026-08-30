variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "connection_arn" {
  type = string
}

variable "artifact_bucket_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "booking_service_name" {
  type = string
}

variable "driver_service_name" {
  type = string
}

variable "tracking_service_name" {
  type = string
}

variable "tags" {
  type = map(string)
}
