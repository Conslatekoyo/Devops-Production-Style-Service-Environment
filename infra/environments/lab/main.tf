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

module "driver_service" {
  source = "../../modules/ecs-service"

  service_name   = "devops-g8-driver-service"
  container_port = 3002
  desired_count  = 1

  register_with_alb    = false
  alb_target_group_arn = null

  image_repo_url = module.workloads.ecr_repository_urls["driver-service"]
  image_tag      = var.driver_image_tag

  health_check_path = "/health"

  cluster_arn        = module.ecs_platform.cluster_arn
  namespace_arn      = module.ecs_platform.service_connect_namespace_arn
  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.driver_task_role_arn

  private_subnet_ids = module.network.private_subnet_ids
  security_group_id  = module.security.driver_security_group_id
  log_group_name     = module.workloads.log_group_names["driver-service"]

  environment_variables = {
    PORT          = "3002"
    BIND_HOST     = "0.0.0.0"
    SERVICE_C_URL = "http://tracking-service:3003"
  }

  cpu    = 256
  memory = 512
  tags   = var.tags
}

module "tracking_service" {
  source = "../../modules/ecs-service"

  service_name   = "devops-g8-tracking-service"
  container_port = 3003
  desired_count  = 1

  register_with_alb    = false
  alb_target_group_arn = null

  image_repo_url = module.workloads.ecr_repository_urls["tracking-service"]
  image_tag      = var.tracking_image_tag

  health_check_path = "/health"

  cluster_arn        = module.ecs_platform.cluster_arn
  namespace_arn      = module.ecs_platform.service_connect_namespace_arn
  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.tracking_task_role_arn

  private_subnet_ids = module.network.private_subnet_ids
  security_group_id  = module.security.tracking_security_group_id
  log_group_name     = module.workloads.log_group_names["tracking-service"]

  environment_variables = {
    PORT          = "3003"
    BIND_HOST     = "0.0.0.0"
    SERVICE_A_URL = "http://booking-service:3001"
  }

  cpu    = 256
  memory = 512
  tags   = var.tags
}

module "booking_service" {
  source = "../../modules/ecs-service"

  service_name   = "devops-g8-booking-service"
  container_port = 3001
  desired_count  = 2

  register_with_alb    = true
  alb_target_group_arn = module.alb.booking_target_group_arn

  image_repo_url = module.workloads.ecr_repository_urls["booking-service"]
  image_tag      = var.booking_image_tag

  health_check_path = "/health"

  cluster_arn        = module.ecs_platform.cluster_arn
  namespace_arn      = module.ecs_platform.service_connect_namespace_arn
  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.booking_task_role_arn

  private_subnet_ids = module.network.private_subnet_ids
  security_group_id  = module.security.booking_security_group_id
  log_group_name     = module.workloads.log_group_names["booking-service"]

  environment_variables = {
    PORT                = "3001"
    BIND_HOST           = "0.0.0.0"
    SERVICE_B_URL       = "http://driver-service:3002"
    AWS_REGION          = var.aws_region
    PENDING_RIDES_TABLE = module.workloads.booking_table_name
  }

  cpu    = 256
  memory = 512
  tags   = var.tags
}

module "cicd" {
  source = "../../modules/cicd"

  name_prefix    = var.name_prefix
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id

  github_owner  = "Conslatekoyo"
  github_repo   = "Devops-Production-Style-Service-Environment"
  github_branch = "main"

  connection_arn = "arn:aws:codeconnections:eu-west-3:240462142849:connection/1fc881ad-de7f-4d37-b7a1-11e1bd1877b8"

  artifact_bucket_name = "devops-g8-codepipeline-artifacts-240462142849"

  cluster_name = "devops-g8-cluster"

  booking_service_name  = "devops-g8-booking-service"
  driver_service_name   = "devops-g8-driver-service"
  tracking_service_name = "devops-g8-tracking-service"

  tags = var.tags
}
