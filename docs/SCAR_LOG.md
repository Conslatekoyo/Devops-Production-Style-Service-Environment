# Scar Log — Group 8
Field format per assignment: Symptom | First hypothesis | Evidence | Actual cause | Repair | Prevention

---

## Scar 1 — CodeBuild couldn't find the buildspec (Hawa, driver-service / tracking-service)

| Field | Entry |
|---|---|
| Symptom | CodePipeline's Build stage failed immediately during DOWNLOAD_SOURCE. |
| First hypothesis | CodeBuild project or IAM permissions were misconfigured. |
| Evidence | Build log: `YAML_FILE_ERROR: stat .../buildspecs/tracking-service.yml: no such file or directory`. The buildspec existed on the feature branch but not on `main`, which the pipeline actually watches. |
| Actual cause | The pipeline ran before the buildspec had been merged into `main`. |
| Repair | Merged the feature branch into `main`, started a fresh pipeline execution. |
| Prevention | Confirm required pipeline files are already on the monitored branch before triggering a build — a pipeline can only see what's on the branch it watches, not what's on your feature branch. |

---

## Scar 2 — Pipeline appeared to skip the rollback test (Hawa, driver-service)

| Field | Entry |
|---|---|
| Symptom | ECS still showed the old task definition revision even after a rollback-test commit was merged. |
| First hypothesis | The ECS deployment circuit breaker wasn't working. |
| Evidence | The pipeline execution being inspected was tied to an *older* commit, not the rollback-test merge — checked the execution's commit hash directly and it didn't match. |
| Actual cause | Was diagnosing a stale/earlier pipeline execution, not the one that actually corresponded to the rollback-test merge. |
| Repair | Started a new execution, explicitly confirmed it was running the correct commit before continuing to monitor it. |
| Prevention | Always check the pipeline execution's commit hash before diagnosing deployment behavior — don't assume the most recent-looking execution is the one you think it is. |

---

## Scar 3 — ECR image push failed on tag mismatch (Hawa, driver-service)

| Field | Entry |
|---|---|
| Symptom | Docker push to ECR failed. |
| First hypothesis | The ECR repository didn't exist, or Docker auth had expired. |
| Evidence | Push error indicated the image tag didn't exist locally — the image had been built with one tag, but the push command referenced a different tag (`latest` vs. the commit SHA). |
| Actual cause | Tag used at build time didn't match the tag used at push time. |
| Repair | Retagged the image with the correct commit SHA and pushed again. |
| Prevention | Use one consistent tag (the commit SHA) throughout build and push, and automate the tagging inside the buildspec so it can't drift. |

---

## Scar 4 — CodePipeline denied writing to the S3 artifact bucket (Hawa, driver-service — also independently hit by Glory, booking-service)

| Field | Entry |
|---|---|
| Symptom | Pipeline's Source stage failed before reaching Build. |
| First hypothesis | The GitHub CodeConnection or repo config was wrong. |
| Evidence | Pipeline logs showed `AccessDenied` when uploading artifacts to the S3 artifact bucket. |
| Actual cause | The CodePipeline IAM role was missing `s3:PutObject` on the artifact bucket. `AWSCodePipeline_FullAccess` — despite the name — does not include this. |
| Repair | Added an explicit IAM policy granting `s3:PutObject` (and related S3 actions) scoped to the artifact bucket. |
| Prevention | Verify the pipeline role's S3 permissions during initial setup, before assuming the "FullAccess" managed policy covers everything the name implies. |

---

## Scar 5 — CodeBuild couldn't be started by the pipeline (Hawa, driver-service — also independently hit by Glory, booking-service)

| Field | Entry |
|---|---|
| Symptom | Build stage failed right after Source succeeded. |
| First hypothesis | The buildspec itself had an error. |
| Evidence | AWS reported CodePipeline couldn't start the CodeBuild project — missing API permission, not a build error. |
| Actual cause | The CodePipeline role lacked `codebuild:StartBuild` and `codebuild:BatchGetBuilds`. |
| Repair | Attached an IAM policy granting both actions to the pipeline role. |
| Prevention | Include CodeBuild trigger permissions on the pipeline role from the start, rather than discovering the gap only once a real build attempt fails. |

---

## Scar 6 — CodeBuild couldn't download its own source artifact (Hawa, driver-service — also independently hit by Glory, booking-service)

| Field | Entry |
|---|---|
| Symptom | Build stage failed during source download, after successfully starting. |
| First hypothesis | The artifact bucket or buildspec was misconfigured. |
| Evidence | CodeBuild logs showed `AccessDenied` fetching the source artifact from S3. |
| Actual cause | The CodeBuild role (separate from the CodePipeline role) lacked `s3:GetObject` on the artifact bucket. |
| Repair | Attached an IAM policy granting `s3:GetObject`/`s3:GetObjectVersion` to the CodeBuild role specifically. |
| Prevention | Remember CodeBuild and CodePipeline are two separate IAM identities with separate permission needs on the same bucket — granting one doesn't grant the other. |

---

## Scar 7 — Service Connect alias mismatch broke the tracking→booking callback (Conslate, tracking-service)

| Field | Entry |
|---|---|
| Symptom | Real `/request-ride` requests through the ALB returned a 504 timeout ("No drivers available") even though all three services reported healthy. |
| First hypothesis | A security group was blocking one of the internal hops. |
| Evidence | Traced the same `ride_id` across all three services' CloudWatch logs. booking→driver succeeded. driver→tracking connected, but tracking's own log showed `error: "fetch failed"` trying to call back to booking-service — a connection-level failure, not an app error. SG rules were independently confirmed correct, ruling out the network layer. |
| Actual cause | booking-service's registered Service Connect alias was the namespace-qualified form (`booking-service.group8.internal`), but tracking-service's `SERVICE_A_URL` used the bare short name (`booking-service`) — which was never registered under that form. |
| Repair | Updated tracking-service's `SERVICE_A_URL` to the correct, matching alias and redeployed. |
| Prevention | Standardize on one Service Connect naming convention (bare name or namespace-qualified) across all services from the start, and verify every service's downstream URL matches what its target actually publishes — don't assume consistency across independently-configured services. |

---

## Scar 8 — Booking-service's in-memory ride state didn't survive its own horizontal scaling (Glory, booking-service) — the team's strongest scar

| Field | Entry |
|---|---|
| Symptom | Even after Scar 7's fix, `/request-ride` still failed intermittently — not 0%, not 100%. A real test batch showed only 3 of 8 requests succeeding. |
| First hypothesis | Residual DNS/timing flakiness left over from the Scar 7 fix — maybe Service Connect hadn't fully propagated. |
| Evidence | Re-ran identical requests repeatedly; the failure rate stayed roughly constant instead of improving, ruling out a propagation/timing explanation. Pulled CloudWatch logs by task ID for a specific failing request and found the exact mismatch directly: `ride_requested` logged on task A, but `tracking_callback_received` for the *same ride ID* logged on task B — a completely different container. |
| Actual cause | booking-service runs desired count 2 (two independent replicas). Pending-ride state was held in a plain in-memory JavaScript `Map`, private to whichever replica's process created it. Since Service Connect load-balances the tracking-service callback across both replicas, roughly half the time it lands on the replica that never received the original request — which has no record of the ride, so the original request's connection times out waiting for an answer that was actually delivered, just to the wrong process. |
| Repair | Replaced the in-memory `Map` with a shared DynamoDB table (`devops-g8-pending-rides`). `/request-ride` now writes a pending record and polls that shared table every 300ms (instead of waiting on a local Promise); `/ride-confirmed` writes the confirmation to the same shared record regardless of which replica receives the callback. Verified with a controlled before/after test on identical traffic: 3/8 successful before the fix, 8/8 successful after. |
| Prevention | Horizontal scaling (`desiredCount > 1`) and per-request correlation state stored in process memory are fundamentally incompatible — this should be checked explicitly during Gate 1 planning whenever a service both scales beyond 1 replica and needs to correlate an async callback to a specific in-flight request. |

---

## Scar 9 — ALB couldn't reach a healthy, running task (Glory, booking-service)

| Field | Entry |
|---|---|
| Symptom | ALB reported `Target.Timeout` on a task that ECS showed as `RUNNING` and `HEALTHY`. |
| First hypothesis | The container itself was broken or slow to respond. |
| Evidence | `describe-target-health` showed "Request timed out" while ECS's own view of the task was fully healthy — ruling out an application-level problem. |
| Actual cause | booking-service's security group had zero inbound rules at all — nothing was explicitly allowed in, including the ALB itself. |
| Repair | Added an explicit inbound rule allowing the ALB's security group on the application port. |
| Prevention | Security groups deny by default; never assume a resource can reach another just because both are "up" — test the actual permitted path explicitly. |

---

## Scar 10 — ECS tasks failed to start on a missing logging permission (Glory, booking-service)

| Field | Entry |
|---|---|
| Symptom | New booking-service tasks failed to reach `RUNNING`. |
| First hypothesis | A bad execution role attachment. |
| Evidence | ECS service events showed the exact error: `AccessDeniedException` on `logs:CreateLogGroup`. |
| Actual cause | The task definition had `awslogs-create-group: true`, but `AmazonECSTaskExecutionRolePolicy` only grants `logs:CreateStream` and `logs:PutLogEvents` — not `CreateLogGroup`. |
| Repair | Manually created the log group ahead of time, so the role's existing permissions (create stream, put events) were sufficient. |
| Prevention | Either pre-create log groups explicitly, or add `logs:CreateLogGroup` to the execution role — don't rely on the managed policy covering it. |

---

## Scar 11 — Gate 3B rollback (Glory, booking-service) — deliberate, controlled test

| Field | Entry |
|---|---|
| Symptom | N/A — intentionally induced for Gate 3B evidence. |
| First hypothesis | N/A |
| Evidence | Deliberately renamed the `/health` route to `/health-broken`, merged to `main`. New tasks (revision 4) failed their health check 4 times in a row. |
| Actual cause | N/A — working as designed. |
| Repair | ECS's deployment circuit breaker automatically marked the rollout `FAILED` and kept the prior working revision (3) active the entire time — `runningCount: 2, failedTasks: 0` throughout, zero user-facing impact. Reverted the deliberate break afterward and redeployed the working code. |
| Prevention | N/A — this scar exists to prove the safety net works, not to prevent a real failure. |

---

## Open item — automatic pipeline trigger unreliable (team-wide, unresolved as of writing)

| Field | Entry |
|---|---|
| Symptom | Merges to `main` sometimes don't trigger CodePipeline automatically at all — confirmed via CloudWatch showing zero invocations on a manually-created EventBridge rule during a real merge. |
| First hypothesis | Rule/target/role misconfiguration on the AWS side. |
| Evidence | Independently verified the EventBridge rule, its target, and its IAM role were all correctly configured — yet zero invocations were recorded. This points upstream, to GitHub not delivering the event to AWS at all. |
| Actual cause | Unconfirmed — requires GitHub repo admin access (webhook delivery log or GitHub App installation status) to diagnose further. |
| Repair | Not yet applied. Using manual "Release change" as a stopgap to keep testing/deploying. |
| Prevention | To be determined once root cause is confirmed — flagged to the repo owner for investigation before the live demo. |
