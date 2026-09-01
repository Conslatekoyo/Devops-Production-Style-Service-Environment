# Gate 3 — Operate: Immutable Release

**Captured:** 2026-09-01, against live devops-g8 infrastructure in the new
AWS account (`240462142849`, `eu-west-3`).

## Why this document exists

`infra/environments/lab/terraform.tfvars` holds the `driver_image_tag`,
`tracking_image_tag` and `booking_image_tag` inputs that drive which image
each service deploys — it is intentionally gitignored (per
`infra/environments/lab/terraform.tfvars.example`) so environment-specific
release state never lives in source control. That means the actual record
of *what was released, when, and how it was proven* has to live somewhere
committed — this file is that record, following the same pattern as
`GATE1_PLANNING.md` and `GATE2_EVIDENCE.md`.

## Release chain

```
Code change → Git commit 0ede411 → Docker build → ECR push → digest
  → terraform.tfvars: driver_image_tag = "0ede411" → plan → apply
  → ECS rolling deployment → verify new SHA
```

| Step | Evidence |
|---|---|
| App change | `services/driver-service/index.js` — `/health` response `message` field updated to end in `- immutable release verified` |
| Git commit | `0ede411` — "Verify immutable driver release" |
| Image build + push | `240462142849.dkr.ecr.eu-west-3.amazonaws.com/devops-g8-driver-service:0ede411` |
| ECR digest | `sha256:e92f783a7c940b4a2cd544f5c4d97c7d07370a926e133b705999569eeca0ff1f`, pushed `2026-09-01T05:52:06+03:00` |
| Terraform input | `driver_image_tag = "0ede411"` in the (gitignored) `terraform.tfvars` |
| Plan reviewed | `terraform plan` showed only `module.driver_service.aws_ecs_task_definition.this` (new revision) and the service update — no other resource touched |
| Apply | New task definition `devops-g8-driver-service-task:2` registered; `devops-g8-driver-service` updated to point at it |

## Rollout verification

```json
{
  "Status": "ACTIVE", "Desired": 1, "Running": 1, "Pending": 0,
  "Deployments": [{
    "Status": "PRIMARY",
    "TaskDef": "arn:aws:ecs:eu-west-3:240462142849:task-definition/devops-g8-driver-service-task:2",
    "Desired": 1, "Running": 1, "Rollout": "COMPLETED"
  }]
}
```

Deployment circuit breaker was armed (`enable = true, rollback = true`); the
rollout completed cleanly with no rollback triggered.

**Immutable-image proof — running container digest matches the ECR digest
for tag `0ede411` exactly, not just the tag name:**

```json
{
  "name": "devops-g8-driver-service",
  "image": "240462142849.dkr.ecr.eu-west-3.amazonaws.com/devops-g8-driver-service:0ede411",
  "imageDigest": "sha256:e92f783a7c940b4a2cd544f5c4d97c7d07370a926e133b705999569eeca0ff1f",
  "lastStatus": "RUNNING",
  "healthStatus": "HEALTHY",
  "startedAt": "2026-09-01T05:58:05.200000+03:00"
}
```

This is stronger than confirming the tag name — a mutable tag could in
principle be repointed, but the running container's digest was checked
directly against ECR's digest for that tag and they match exactly.

## Post-release traffic proof (system still works after rollout)

Live request through the ALB, after the new revision was running:

```
$ curl -i -X POST http://devops-g8-alb-1566487128.eu-west-3.elb.amazonaws.com/request-ride \
    -H "X-Request-ID: release-verify-1788230500-001" \
    -d '{"pickup":"Post-Release-A","dropoff":"Post-Release-B"}'
HTTP/1.1 200 OK
{"ride_id":"release-verify-1788230500-001","status":"confirmed", ...}
```

Same `ride_id` traced across all three CloudWatch log groups, confirming
the full Booking → Driver → Tracking → Booking-callback loop still works
on the new Driver revision:

| Service | Events |
|---|---|
| booking-service | `ride_requested` → `driver_assignment_requested` (200) → `tracking_callback_received` → `ride_confirmed` |
| driver-service | `driver_assignment_started` → `tracking_started` (200) |
| tracking-service | `tracking_started` → `booking_confirmation_sent` (200) |

## Verdict

- **Immutable release: verified.** Digest-level match between the deployed
  tag and the running container, not just a tag-name check.
- **Zero-downtime rollout: verified.** Circuit breaker armed, single
  `COMPLETED` deployment, no rollback.
- **Post-release functional proof: verified.** Full A→B→C→callback loop
  confirmed live after the rollout via a fresh traced request.
