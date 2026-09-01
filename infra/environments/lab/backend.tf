terraform {
  backend "s3" {
    bucket       = "devops-g8-tfstate-240462142849-eu-west-3"
    key          = "group8/lab/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}
