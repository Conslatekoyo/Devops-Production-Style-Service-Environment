############################################
# variables — ecs-service module
# (generic inputs, no service-specific
#  hardcoding — this must work identically
#  for booking, driver, and tracking)
############################################

variable "service_name" {
  type        = string
  description = "Fully qualified Group 8 service name."

  validation {
    condition = contains([
      "devops-g8-booking-service",
      "devops-g8-driver-service",
      "devops-g8-tracking-service"
    ], var.service_name)

    error_message = "service_name must be one of the approved Group 8 service names."
  }
}

variable "container_port" {
  type        = number
  description = "Container port exposed by the service."

  validation {
    condition     = contains([3001, 3002, 3003], var.container_port)
    error_message = "container_port must be 3001, 3002 or 3003."
  }
}

variable "desired_count" {
  type        = number
  description = "Number of Fargate tasks maintained by the ECS service."

  validation {
    condition     = var.desired_count >= 1
    error_message = "desired_count must be at least 1."
  }
}

variable "register_with_alb" {
  type        = bool
  default     = false
  description = "Only booking-service sets this true"
}

variable "alb_target_group_arn" {
  type    = string
  default = null
}

variable "image_repo_url" {
  type = string
}

variable "image_tag" {
  type        = string
  description = "Immutable 7-40 character lowercase hexadecimal Git commit SHA."

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.image_tag))
    error_message = "image_tag must be a 7-40 character lowercase hexadecimal Git commit SHA."
  }
}

variable "health_check_path" {
  type        = string
  description = "Container health-check endpoint."
  default     = "/health"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must begin with /."
  }
}

variable "cluster_arn" {
  type = string
}

variable "namespace_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Services must be placed across at least two private subnets (two AZs)."
  }
}

variable "security_group_id" {
  type = string
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "log_group_name" {
  type = string
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "tags" {
  type        = map(string)
  description = "Required tags applied to the task definition and ECS service."

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

############################################
# task definition
############################################

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.service_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = "${var.image_repo_url}:${var.image_tag}"
      essential = true

      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
        name          = var.service_name # named port — required for Service Connect
        appProtocol   = "http"
      }]

      environment = [
        for k, v in var.environment_variables : { name = k, value = v }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = var.service_name
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O- http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 10
        timeout     = 3
        retries     = 5
        startPeriod = 10
      }
    }
  ])

  tags = var.tags
}

data "aws_region" "current" {}

############################################
# ECS service
# (public IP is never exposed as a variable
#  here at all — rule #1 enforced by simply
#  not offering the option)
############################################

resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = var.namespace_arn

    service {
      port_name      = var.service_name
      discovery_name = replace(var.service_name, "devops-g8-", "") # e.g. "booking-service"

      client_alias {
        port     = var.container_port
        dns_name = replace(var.service_name, "devops-g8-", "")
      }
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  enable_execute_command = true

  dynamic "load_balancer" {
    for_each = var.register_with_alb ? [1] : []
    content {
      target_group_arn = var.alb_target_group_arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  lifecycle {
    precondition {
      condition     = var.register_with_alb == false || var.alb_target_group_arn != null
      error_message = "register_with_alb is true but no alb_target_group_arn was provided."
    }

    precondition {
      condition = (
        var.register_with_alb == false ||
        var.service_name == "devops-g8-booking-service"
      )

      error_message = "Only devops-g8-booking-service may register with the Application Load Balancer."
    }
  }

  tags = var.tags
}

############################################
# outputs
############################################

output "service_arn" {
  value = aws_ecs_service.this.id
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "service_name" {
  value = aws_ecs_service.this.name
}
