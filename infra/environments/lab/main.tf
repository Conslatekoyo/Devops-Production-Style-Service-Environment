module "network" {
  source = "../../modules/network"

  name_prefix          = var.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  tags                 = var.tags
}

module "ecs_platform" {
  source = "../../modules/ecs-platform"

  name_prefix               = var.name_prefix
  cluster_name              = "devops-g8-cluster"
  service_connect_namespace = "group8.internal"
  enable_container_insights = true
  exec_log_group_name       = "/ecs/devops-g8-exec"
  exec_log_retention_days   = 14
  tags                      = var.tags
}

module "iam" {
  source = "../../modules/iam"

  name_prefix                = var.name_prefix
  ecs_exec_log_group_arn     = module.ecs_platform.ecs_exec_log_group_arn
  booking_dynamodb_table_arn = module.workloads.booking_table_arn
  tags                       = var.tags
}

module "security" {
  source = "../../modules/security"

  name_prefix = var.name_prefix
  vpc_id      = module.network.vpc_id
  tags        = var.tags
}

module "alb" {
  source = "../../modules/alb"

  name_prefix           = var.name_prefix
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  booking_port          = 3001
  health_check_path     = "/health"
  target_type           = "ip"
  tags                  = var.tags
}

module "workloads" {
  source = "../../modules/workloads"

  name_prefix = var.name_prefix
  tags        = var.tags
}
