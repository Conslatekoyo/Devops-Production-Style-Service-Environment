# Gate 2 — Runtime and Security Proof

**Captured:** 2026-07-22, updated 2026-07-24 against live devops-g8 infrastructure (eu-west-3).

## Public request

```
$ curl -i http://devops-g8-alb-1127437633.eu-west-3.elb.amazonaws.com/health
HTTP 200 in 0.44s
```

## Positive tests

| Test | Where executed | Result | Evidence |
|---|---|---|---|
| Internet → ALB | This machine | **Allowed** | `curl http://devops-g8-alb-.../health` → `HTTP 200` in 0.44s |
| ALB → booking-service | Through the public request above | **Allowed** | Same request — ALB only forwards to a registered, healthy target; target group `devops-g8-booking-tg` shows healthy targets on :3001 |
| booking-service → driver-service | Live traffic (`POST /request-ride`) | **Allowed** | booking-service log: `driver_assignment_requested` ... `status:200`; driver-service log: `driver_assignment_started` for the same `ride_id` |
| driver-service → tracking-service | Live traffic (`POST /request-ride`) | **Allowed** | tracking-service log: `tracking_started` received the POST from driver-service for the same `ride_id` |
| tracking-service → booking-service (callback) | Live traffic (`POST /ride-confirmed`) | **Allowed** | booking-service log: `tracking_callback_received` for the same `ride_id`, followed by `ride_confirmed` once the polling loop picks up the shared DynamoDB record |

## Negative tests

| Test | Where executed | Result | Evidence |
|---|---|---|---|
| Internet → booking-service :3001 | This machine, direct to task public IP | **Denied** | `curl --max-time 5` → connection timed out |
| Internet → driver-service :3002 | This machine, direct to task public IP | **Denied** | `curl --max-time 5` → connection timed out |
| Internet → tracking-service :3003 | This machine, direct to task public IP | **Denied** | `curl --max-time 5` → connection timed out |
| booking-service → tracking-service (direct) | Not exercised by the app (no code path calls this) | **Denied by config** | Security-group rule audit: `devops-g8-tracking-service-sg` only permits inbound :3003 from `devops-g8-driver-service-sg` — no rule references the booking-service SG at all |

## Security-group rule audit (evidence type 1)

```
devops-g8-alb-sg:              inbound 80/tcp  from 0.0.0.0/0
devops-g8-booking-service-sg:  inbound 3001/tcp from sg-053f8311af60b4247 (alb-sg)
                                                 and sg-04936ddf7375b135f (tracking-service-sg)
devops-g8-driver-service-sg:   inbound 3002/tcp from sg-0d8cb70472d5e805f (booking-service-sg)
devops-g8-tracking-service-sg: inbound 3003/tcp from sg-0e26b1763e6e8ddb9 (driver-service-sg)
```

This matches the Gate 1 traffic contract exactly, including the tracking→booking
callback rule that a generic straight-line A→B→C contract wouldn't have predicted.

## CloudWatch Logs (evidence type 2) — traced request

Real ride request fired via:
```
curl -X POST http://devops-g8-alb-.../request-ride \
  -H "Content-Type: application/json" \
  -d '{"pickup":"Westlands","dropoff":"CBD"}'
```

| Hop | Log group | Event |
|---|---|---|
| 1 | `/ecs/devops-g8-booking-service` | `ride_requested` → `driver_assignment_requested` (status 200) |
| 2 | `/ecs/devops-g8-driver-service` | `driver_assignment_started` → successful call to tracking-service |
| 3 | `/ecs/devops-g8-tracking-service` | `tracking_started` → `tracking_callback_received` acknowledged by booking-service |
| 4 | `/ecs/devops-g8-booking-service` | `tracking_callback_received` → `ride_confirmed` (status 200), returned to the original client |

The same `ride_id` appears in all four log lines across all three log groups,
satisfying the correlation-ID requirement.

## Reliability verification — before and after the Scar #8 fix

Two identical 8-request batches were run against `/request-ride`, same payload,
same endpoint, only the deployed code differed:

| Batch | Code under test | Result |
|---|---|---|
| Before fix | booking-service holding pending-ride state in an in-memory `Map` (desired count 2) | **3 of 8** requests confirmed successfully; the rest timed out |
| After fix | booking-service using a shared DynamoDB table (`devops-g8-pending-rides`) with polling | **8 of 8** requests confirmed successfully |

Full diagnosis of the root cause (callback landing on the replica that never
received the original request) is in `SCAR_LOG.md`, Scar #8.

## Gate 2 verdict

- **Positive/negative boundary tests: pass.** Both configuration (SG rules) and
  external runtime behavior (direct-IP connection attempts) agree with the Gate 1
  traffic contract.
- **End-to-end application flow: pass.** The tracking→booking connectivity break
  (Scar #7) and the horizontal-scaling state bug (Scar #8) were both found through
  evidence-driven diagnosis, fixed, and reverified live with a controlled
  before/after test showing the fix's real effect (3/8 → 8/8).
- **Open, unresolved as of writing:** automatic pipeline triggering on merge to
  `main` is unreliable — confirmed zero EventBridge invocations during a real
  merge despite correct rule/target/role configuration on the AWS side. Root
  cause requires GitHub repo admin access to diagnose further (webhook or GitHub
  App delivery status). See `SCAR_LOG.md` open item.
