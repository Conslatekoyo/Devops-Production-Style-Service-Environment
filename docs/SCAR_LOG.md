# Scar Log

## Scar #1 — Ride requests time out; tracking-service can't call back to booking-service

**Owner at time of discovery:** Conslate (tracking-service), during Gate 2 evidence
capture on 2026-07-22.

| Field | Entry |
|---|---|
| Symptom | Real `POST /request-ride` through the ALB returns `{"status":"error","message":"No drivers available — please try again"}` (booking-service's 504-callback-timeout path) even though all three ECS services report `RUNNING`/healthy and desired count is met. |
| First hypothesis | Security group misconfiguration blocking one of the internal hops (A→B or B→C). |
| Evidence | Pulled CloudWatch Logs for the specific `ride_id` across all three log groups. booking→driver succeeded (`status:200`). driver→tracking's HTTP call *connected* (tracking-service received and logged the request) but driver-service recorded the response as `status:502` — and forwarded a false-positive `200 driver_assigned` to booking-service anyway, since `driver-service/index.js:211` calls `response.json()` without checking `response.ok`. tracking-service's own log showed the real failure: `booking_confirmation_failed`, `error: "fetch failed"` — a connection-level failure calling `SERVICE_A_URL`. Cross-checked SG rules (all correct, matched Gate 1 contract) and Service Connect configuration for each service, which ruled out the network/SG layer entirely. |
| Actual cause | DNS alias mismatch in Service Connect. `booking-service`'s registered `clientAlias.dnsName` is `booking-service.group8.internal` (namespace-qualified), but `tracking-service`'s task definition sets `SERVICE_A_URL=http://booking-service:3001` (short name, no namespace suffix). `driver-service`'s alias happens to be registered as the short name `driver-service`, which is why booking→driver and driver→tracking both resolve fine — the inconsistency is specific to booking-service's alias. |
| Repair | **Applied and confirmed live.** Registered a new tracking-service task definition (`devops-g8-tracking-service-task:4`) with `SERVICE_A_URL=http://booking-service.group8.internal:3001`, matching booking-service's actual registered alias. Updated the ECS service to the new revision and waited for steady state. |
| Prevention | Service Connect alias naming wasn't standardized across the three services before wiring — Gate 1 planning should have pinned down one exact DNS-naming convention (either always short-name or always namespace-qualified) and had every task definition's downstream URLs reviewed against it before Gate 2, not discovered by a live failing request. See the Gate 1 doc's recommendation to standardize all three aliases going forward. |

**Recovery confirmation:** re-ran a live `POST /request-ride` immediately after the
service reached steady state on revision 4. The `fetch failed` error was gone —
tracking-service successfully reached booking-service's `/ride-confirmed` endpoint.
This is what led directly to discovering Scar #2 below: the callback now *arrives*,
but doesn't always resolve the right in-memory request.

---

## Scar #2 — Ride requests still fail ~intermittently after Scar #1's fix (open)

**Owner at time of discovery:** Conslate, while retesting the Scar #1 fix on
2026-07-22/23.

| Field | Entry |
|---|---|
| Symptom | After fixing Scar #1, `/request-ride` still fails intermittently rather than consistently. Two separate test batches: 2 of 5 requests succeeded in one run, 2 of 8 succeeded in a later run — never 0% and never 100%, which ruled out "still fully broken" as the explanation. |
| First hypothesis | Residual DNS/timing flakiness from the Scar #1 fix — maybe the new task definition hadn't fully propagated, or Service Connect's Envoy sidecar needed more time to pick up the change. |
| Evidence | Repeated the same live request multiple times back-to-back after confirming the service was stable on revision 4. The failure rate stayed roughly constant across runs rather than improving over time, which ruled out a propagation/timing explanation. Checked booking-service's ECS service configuration: `desiredCount: 2` — two independent task replicas. Read `services/booking-service/index.js`: pending ride state (`pendingCallbacks`) is stored in a plain in-memory `Map`, local to a single Node.js process. |
| Actual cause | booking-service runs two replicas behind Service Connect, which load-balances the tracking-service callback (`POST /ride-confirmed`) across both. The replica that *originally* received `/request-ride` is the only one holding the pending promise for that ride ID in its own memory. When the callback happens to land on the *other* replica, that replica has no matching entry, silently returns `{"status":"received"}` anyway, and the original replica's request times out 10 seconds later. This is a structural application-design issue, not a config typo — it will keep happening at roughly the rate implied by however many replicas are running (theoretically ~50% at desired count 2), for every request, indefinitely. |
| Repair | **Not applied — requires a decision, not just a fix.** This is booking-service's application code (Glory's owned service); per the team's ownership rule it shouldn't be patched unilaterally. Options recorded for the team: (1) move pending-ride state to a shared store (e.g. Redis/DynamoDB) so any replica can resolve any pending ride; (2) redesign `/request-ride` to not hold a synchronous connection open across a cross-replica callback (e.g. return immediately, let the client poll ride status); (3) as a stopgap only, temporarily run booking-service at desired count 1 — but this defeats the Phase 4.3/Demo 5 kill-a-task availability demonstration, which specifically needs 2 replicas. |
| Prevention | The reliability implications of `desiredCount: 2` combined with in-memory, per-request correlation state should have been reviewed together during Gate 1 planning — horizontal scaling and stateful request-handling are a known incompatible combination, and this is exactly the kind of interaction a dependency-graph review is meant to surface before it's live. |

---

_Add further entries above this line, most recent first is fine — keep each entry to the five required fields._
