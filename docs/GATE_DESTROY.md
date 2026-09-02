# Operate Cycle -- Teardown and Cost Sweep

**Executed by:** Glory Wachira, with explicit consent from Hawaah and Conslate
(both had already captured or confirmed they no longer needed the live
environment). **Date:** 2026-09-02. **Account:** 240462142849, region
eu-west-3.

## Why this exists

The assignment's Operate cycle closes with proving that teardown actually
removes what it claims to, not just trusting `terraform destroy`'s exit
code. This document is that proof -- matching Scenario E's lesson from
earlier training: destroy is only verified once you check the real cloud
environment against the expected empty state, not before.

## Destroy

```
terraform plan -destroy -out=destroy.tfplan
```
Plan: 0 to add, 0 to change, **63 to destroy**.

```
terraform apply "destroy.tfplan"
```
Apply complete! Resources: 0 added, 0 changed, **63 destroyed**.

## Post-destroy verification (evidence, not assumption)

| Resource | Check | Result |
|---|---|---|
| ECS cluster | `aws ecs list-clusters` | `[]` -- gone |
| ECS services | `aws ecs list-services --cluster devops-g8-cluster` | `[]` -- gone |
| Application Load Balancer | `aws elbv2 describe-load-balancers` filtered to `devops-g8` | `[]` -- gone |
| ECR repositories | `aws ecr describe-repositories` filtered to `devops-g8` | `[]` -- gone. Terraform destroyed the repositories themselves, not just the ECS layer -- confirmed by `RepositoryNotFoundException` when querying images directly, meaning all three services' pushed images (including the SHA-tagged releases from Gate 3 and the Teach cycle) were removed along with the repos. |
| DynamoDB tables | `aws dynamodb list-tables` filtered to `devops-g8` | Only `devops-g8-tf-lock` remains |

## What was intentionally left in place

- **`devops-g8-tf-lock`** (DynamoDB) -- Terraform's own state-locking table,
  part of the backend configuration in `backend.tf`, not application
  infrastructure. Expected to persist so the backend remains usable if the
  environment is ever redeployed.
- **The S3 state bucket** (`devops-g8-tfstate-240462142849-eu-west-3`) --
  same reasoning: backend infrastructure, holds the Terraform state history
  itself, not something `terraform destroy` (run against the `lab`
  environment's own resources) would or should remove.

## Verdict

- **Teardown: verified complete.** Every application-layer resource
  (compute, load balancing, image storage) confirmed absent via direct AWS
  API queries, not inferred from Terraform's own exit status.
- **No orphaned billable resources found.** ECR image storage -- often an
  easy thing to leave behind since Terraform's `aws_ecr_repository` resource
  needed `force_delete` or manual image cleanup in many setups -- was
  confirmed gone rather than assumed.
- **Backend infrastructure correctly retained**, distinguishing "the
  environment we tore down" from "the mechanism that lets us stand it back
  up again."
