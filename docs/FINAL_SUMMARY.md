# Final Submission Summary -- Group 8

**Group:** devops-g8 -- **Region:** eu-west-3 -- **Account:** 240462142849
**Team:** Glory (booking-service), Hawaah (driver-service, platform), Conslate (tracking-service)
**Date:** 2026-09-02

This document ties together the group's full body of evidence, produced across
five stages, into one submission-ready summary. Each stage has its own
detailed document; this file is the index and the headline result for each.

## 1. Planning and architecture -- `docs/GATE1_PLANNING.md`

Dependency graph, ownership map, resource naming, traffic contracts, and
failure predictions -- written and verified against the live system rather
than as a pre-build guess. Confirmed: three services (booking, driver,
tracking) on ECS Fargate behind an ALB, wired internally via Service Connect,
with a non-linear traffic pattern (tracking calls back to booking, not a
straight line).

**Note:** this document currently references the group's original AWS account
(827478161993). It should be updated to the current account (240462142849)
before final submission -- everything else in it (architecture, contracts,
ownership) remains accurate.

## 2. Runtime and security proof -- `docs/GATE2_EVIDENCE.md`

Positive and negative connectivity tests against the live system: the ALB
path works end-to-end (`curl` -> 200 OK), and every direct-to-service path
that should be blocked, is -- confirmed both by security-group rule audit and
by live connection attempts timing out from the internet. Full request trace
across all three services' CloudWatch logs, correlated by `ride_id`.

Includes the before/after reliability proof for Scar 8 (see below):
3 of 8 requests succeeding before the fix, 8 of 8 after.

## 3. Diagnosed failures -- `docs/SCAR_LOG.md`

Eleven scars, each with symptom, first hypothesis, evidence, actual root
cause, repair, and prevention:

- Scars 1-6 (Hawaah, driver-service): CodePipeline/CodeBuild/IAM permission
  gaps -- artifact bucket access, build-trigger permissions, source download
  permissions, tag mismatches, stale-execution misdiagnosis.
- **Scar 7** (Conslate, tracking-service): a Service Connect alias mismatch
  broke the tracking-to-booking callback -- diagnosed by tracing a single
  `ride_id` across all three services' logs and finding the exact hop where
  it failed.
- **Scar 8** (Glory, booking-service) -- the team's strongest finding:
  booking-service held pending-ride state in a process-local in-memory `Map`
  while running at desired count 2. Tracking's callback, load-balanced across
  both replicas, landed on the "wrong" replica roughly half the time,
  producing an intermittent (not total) failure that took real diagnosis to
  catch -- confirmed via task-level CloudWatch log correlation showing the
  request and its callback on two different tasks. Fixed by moving pending
  state to a shared DynamoDB table. Verified 3/8 -> 8/8 on identical traffic.
- Scar 9 (Glory, booking-service): a security group with zero inbound rules
  silently blocked the ALB despite ECS reporting the task healthy.
- Scar 10 (Glory, booking-service): a missing `logs:CreateLogGroup`
  permission on the execution role, despite the managed policy's name
  suggesting full logging access.
- Scar 11 (Glory, booking-service): a deliberate, controlled failure
  (renamed `/health` route) to prove the ECS deployment circuit breaker
  actually works -- confirmed zero user-facing impact during a failed
  rollout.
- **Open, unresolved:** automatic pipeline triggering on merge to `main` is
  unreliable. EventBridge rule/target/role are all confirmed correctly
  configured on the AWS side with zero invocations recorded, pointing at a
  GitHub-side delivery issue that needs repo admin access to diagnose
  further.

## 4. Immutable release proof -- `docs/GATE3_OPERATE.md`

Hawaah's release-and-prove cycle for driver-service: a code change traced
through commit -> image build -> ECR push -> digest -> Terraform input ->
plan -> apply -> ECS rollout, verified at the **image digest level** (not
just tag name) against the running container, plus a full post-release
traffic trace confirming the entire A->B->C->callback loop still worked
after the deploy.

## 5. Independent verification (Teach cycle) -- `docs/GATE_TEACH.md`

Glory (booking-service owner) independently authenticated with her own AWS
SSO session and, using a completely clean checkout unrelated to any existing
work, ran `terraform init` -> `plan` -> `apply` from scratch against the live
environment. The plan correctly detected real drift (deployed image tags
were stale relative to the newest pushed images); with Hawaah's consent, the
drift was applied, moving all three services onto a new release. The new
release was verified with the same rigor as Gate 3: task health, target
health, and a full cross-service log trace of a single request ID through
booking -> driver -> tracking -> booking-callback.

## 6. Individual evidence -- `evidence/booking-service/`

Glory's Booking-specific verification: service status (2/2, no public IP),
ALB target health (both healthy, two AZs), runtime image confirmed against
the deployed task definition, CloudWatch logs proving the booking-to-driver
health dependency, an external ALB curl test from outside AWS entirely, and
architectural network-denial proof (only booking-service has a target group
at all -- driver and tracking have no path from the ALB or the internet).

## Outstanding items before final close-out

- [ ] Update `docs/GATE1_PLANNING.md`'s account number and re-check its open
      items list against current status (Scar 8 is now fixed, not open;
      the driver-service task-definition rename runbook status should be
      confirmed).
- [ ] Correct `README.md`'s "AWS Deployment (Production)" section -- it
      still describes the original CodePipeline/CodeBuild/CodeConnections
      design (which is what Scars 1-6 were diagnosed against), not the
      current Terraform + GitHub Actions OIDC + ECR pipeline the system
      actually runs on now.
- [ ] Diagnose the still-open automatic-pipeline-trigger issue, or
      explicitly document it as a known limitation with the manual
      "terraform apply" release process as the accepted workaround.
- [ ] `terraform destroy` + cost sweep, once the team confirms no further
      evidence needs to be captured against the live environment.
- [ ] Platform-role rotation decision (Hawaah currently holds both
      driver-service and platform ownership) -- per Gate 1's own
      recommendation, at least one other teammate should be able to answer
      platform-level questions cold before the demo.
