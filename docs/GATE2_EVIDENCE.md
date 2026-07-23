# Gate 2 — Runtime and Security Proof

**Captured:** 2026-07-22, against live devops-g8 infrastructure (eu-west-3).

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
| driver-service → tracking-service | Live traffic (`POST /request-ride`) | **Allowed** (connection succeeds; app-level 502 is a separate issue, see Scar Log #1) | tracking-service log: `tracking_started` received the POST from driver-service for the same `ride_id` |

## Negative tests

| Test | Where executed | Result | Evidence |
|---|---|---|---|
| Internet → booking-service :3001 | This machine, direct to task public IP `13.37.237.170:3001` | **Denied** | `curl --max-time 5` → exit code 28 (connection timed out) |
| Internet → driver-service :3002 | This machine, direct to task public IP `15.237.174.20:3002` | **Denied** | `curl --max-time 5` → exit code 28 (connection timed out) |
| Internet → tracking-service :3003 | This machine, direct to task public IP `15.188.74.162:3003` | **Denied** | `curl --max-time 5` → exit code 28 (connection timed out) |
| booking-service → tracking-service (direct) | Not exercised by the app (no code path calls this) | **Denied by config** | Security-group rule audit: `devops-g8-tracking-service-sg` only permits inbound :3003 from `devops-g8-driver-service-sg` (`sg-0e26b1763e6e8ddb9`) — no rule references the booking-service SG at all |

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

Real ride request, `ride_id=e0ef4fa4-3d8b-4d49-b1c8-9cc2075621fe`, fired via:

```
curl -X POST http://devops-g8-alb-.../request-ride \
  -H "Content-Type: application/json" \
  -d '{"pickup":"Westlands","dropoff":"CBD"}'
```

| Hop | Log group | Event |
|---|---|---|
| 1 | `/ecs/devops-g8-booking-service` | `ride_requested` → `driver_assignment_requested` (status 200) |
| 2 | `/ecs/devops-g8-driver-service` | `driver_assignment_started` → `tracking_started` (status **502**, see Scar Log #1) |
| 3 | `/ecs/devops-g8-tracking-service` | `tracking_started` → `booking_confirmation_failed` (`error: fetch failed`) |
| 4 | `/ecs/devops-g8-booking-service` | `ride_confirmation_timeout` (status 504) after 10s |

The same `ride_id` appears in all three log groups, satisfying the correlation-ID
requirement — but the trace also surfaced a live production bug rather than a clean
pass. See Scar Log #1 for the diagnosis.

## Gate 2 verdict

- Positive/negative boundary tests: **pass**, both configuration (SG rules) and
  external runtime behavior (direct-IP connection attempts) agree with the Gate 1
  traffic contract.
- End-to-end application flow: **partially passing, one open issue.** The
  tracking→booking connectivity break documented above (Scar #1) was fixed and
  reverified live. A follow-up 8-request test batch after the fix showed 2/8 rides
  confirmed successfully end-to-end — the network/SG/Service-Connect layer is now
  fully working, but a second, structural issue (Scar #2: booking-service's
  in-memory callback state doesn't survive its own 2-replica horizontal scaling)
  causes the remaining failures. Full diagnosis in `SCAR_LOG.md`. Gate 2's
  network/security proof is complete; full end-to-end reliability is not yet, and
  that remaining gap is an application-code fix owned by booking-service's owner.
