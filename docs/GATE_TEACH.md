# Teach Cycle — Independent Verification

**Verified by:** Glory Wachira (booking-service owner), guided/consented by Hawaah (platform owner). **Date:** 2026-09-02. **Account:** 240462142849, region eu-west-3.

## Why this exists

The assignment requires an engineer other than the one who built the platform to independently authenticate and deploy from a clean checkout, proving the process is reproducible and not just something that happens to work on the platform owner's machine.

## Process followed

1. **Fresh clone**, in a directory unrelated to any existing local work: `~/teach-cycle-verification/Devops-Production-Style-Service-Environment`, branch `feature/iac-workloads`.
2. **Independent AWS authentication** -- own AWS SSO login (MFA), own temporary session credentials via `aws sts get-caller-identity`, confirmed assuming `AWSReservedSSO_DevOpsCohort-group8-eu-west-3`.
3. `terraform init` from zero -- backend (S3), all 9 modules, and the AWS provider all resolved and initialized correctly with no manual intervention beyond supplying `terraform.tfvars` (gitignored by design; see `docs/GATE3_OPERATE.md` for why).
4. `terraform plan` correctly detected real drift: the live services were still running older image tags (`7f4af9f` / an intermediate tag) while the newest pushed image (`2b7c972563c839a138b648c898a325e9ead354d2`, all three ECR repos, pushed 2026-09-02) had not yet been deployed. This is Terraform accurately reflecting reality, not an error.
5. Applied the plan: `terraform apply`. Result: 3 added, 3 changed, 3 destroyed -- new task-definition revisions registered (`devops-g8-booking-service-task:2`, `devops-g8-driver-service-task:3`, `devops-g8-tracking-service-task:2`), each service updated to point at its new revision. This is a task-definition replacement (standard immutable-release pattern), not a teardown of the ECS services themselves.

## Post-deploy verification
aws ecs describe-services --cluster devops-g8-cluster --services devops-g8-booking-service devops-g8-driver-service devops-g8-tracking-service

All three: `desired == running`, no failed tasks.

| Service | Desired | Running | Task definition |
|---|---|---|---|
| booking-service | 2 | 2 | `devops-g8-booking-service-task:2` |
| driver-service | 1 | 1 | `devops-g8-driver-service-task:3` |
| tracking-service | 1 | 1 | `devops-g8-tracking-service-task:2` |

## End-to-end traffic proof (new release)
curl -i -X POST http://devops-g8-alb-1566487128.eu-west-3.elb.amazonaws.com/request-ride -H "X-Request-ID: teach-cycle-verify-001" -d '{"pickup":"Teach-A","dropoff":"Teach-B"}'

`HTTP/1.1 200 OK` -- `{"ride_id":"teach-cycle-verify-001","status":"confirmed",...}`

**Full trace across all three services' CloudWatch logs, same request ID, in order:**

| Time (UTC) | Service | Event |
|---|---|---|
| 11:22:15.136 | booking-service | `ride_requested` |
| 11:22:15.567 | driver-service | `driver_assignment_started` (driver drv-003, James Kamau) |
| 11:22:15.601 | tracking-service | `tracking_started` |
| 11:22:16.000 | tracking-service | `booking_confirmation_sent` -> booking-service (200) |
| 11:22:16.006 | driver-service | `tracking_started` -> tracking-service |
| 11:22:16.011 | booking-service | `driver_assignment_requested` -> driver-service (200) |
| 11:22:15.909 | booking-service | `tracking_callback_received` |
| 11:22:16.021 | booking-service | `ride_confirmed` |

Raw filter-log-events JSON for all three services saved in `~/teach-evidence/` on the verifier's machine (booking-trace.json, driver-trace.json, tracking-trace.json).

## Verdict

- **Clean-checkout reproducibility: verified.** An engineer who did not build this platform authenticated independently and ran the full `init` -> `plan` -> `apply` cycle successfully.
- **Drift detection: verified.** Terraform correctly identified real deployed-vs-configured differences rather than reporting a false "no changes."
- **New release, all three services: verified.** Full A -> B -> C -> callback loop confirmed working post-deployment via a single traced request ID across all three CloudWatch log groups.
