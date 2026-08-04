resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = var.exec_log_group_name
  retention_in_days = var.exec_log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-exec-logs"
    }
  )
}

resource "aws_service_discovery_http_namespace" "this" {
  name        = var.service_connect_namespace
  description = "Service Connect namespace for Group 8 Booking, Driver and Tracking services."

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-service-connect-namespace"
    }
  )
}

resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.this.arn
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = false
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )
}
