# Booking Service — Deployment Evidence

Captured against the new AWS account (240462142849, eu-west-3) after the
group's migration off the previous account, per Rob's instructions.

## Files

- **booking-service-status.json** — `aws ecs describe-services`. Confirms:
  2/2 tasks running, status ACTIVE, 0 failed tasks, `assignPublicIp: DISABLED`,
  Fargate launch type, two subnets (multi-AZ), `enableExecuteCommand: true`.

- **target-health.json** — `aws elbv2 describe-target-health`. Confirms both
  ALB targets are `healthy`, one in `eu-west-3a` and one in `eu-west-3b`.

- **task-image.json** — `aws ecs describe-task-definition`. Confirms the
  running image is `devops-g8-booking-service:7f4af9f`, matching the agreed
  initial immutable application version.

- **cloudwatch-logs.txt** — `aws logs tail /ecs/devops-g8-booking-service`.
  Real structured JSON logs showing `/health` returning 200, and Booking's
  own health check self-reporting `"dependencies":{"driver-service":"ok"}` --
  this proves Booking -> Driver connectivity from inside the running task.

- **alb-external-health.txt** — `curl -v` against the ALB's public DNS name
  from an external machine (not inside AWS). Confirms `HTTP/1.1 200 OK` and
  a healthy JSON body, proving the full Internet -> ALB -> Booking path
  works end-to-end.

## Network-denial evidence

`aws elbv2 describe-target-groups` (region-wide) returns exactly one target
group: `devops-g8-booking-tg`. Driver and Tracking have no target group at
all, so there is no ALB or internet-facing path to either service --
confirmed structurally, not just by a failed connection attempt.
