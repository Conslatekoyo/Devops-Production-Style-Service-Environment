# Production Service Environment

Three internal HTTP services orchestrated with Nginx, systemd, and Linux networking on Ubuntu.

## Architecture

```
+-----------------------------------------------------------------------+
|                         Ubuntu VM                                     |
|                                                                       |
|  +--------------+    +-----------------------------------------+    |
|  |   UFW        |    |        Internal Network (127.0.0.1)     |    |
|  |   Firewall   |    |                                         |    |
|  |              |    |  +-----------+      +-----------+       |    |
|  |  Allow:      |    |  | Service B |<-----| Service A |       |    |
|  |   22 (SSH)   |    |  |  :3002    |      |  :3001    |<--+   |    |
|  |   80 (HTTP)  |    |  | /greet    |      | /greet-   |   |   |    |
|  |              |    |  | /health   |      |  service-b|   |   |    |
|  |  Block:      |    |  | /metrics  |      | /greeting-|   |   |    |
|  |   3001       |    |  +-----+-----+      |  rcvd     |   |   |    |
|  |   3002       |    |        |             | /health   |   |   |    |
|  |   3003       |    |        |             | /metrics  |   |   |    |
|  |              |    |        v             +-----^-----+   |   |    |
|  |              |    |  +-----------+            |          |   |    |
|  |              |    |  | Service C |------------+          |   |    |
|  |              |    |  |  :3003    |  callback POST        |   |    |
|  |              |    |  | /greet-c  |  /greeting-rcvd       |   |    |
|  |              |    |  | /health   |                       |   |    |
|  |              |    |  | /metrics  |                       |   |    |
|  |              |    |  +-----------+                       |   |    |
|  |              |    +-----------------------------------------+    |
|  +------+-------+                                           |      |
|         |                                                   |      |
|  +------v-----------------------------------------------------+    |
|  |                    Nginx (:80)                              |    |
|  |  /service-a/*  ->  proxy_pass service-a.internal:3001       |    |
|  |  /*            ->  404                                       |    |
|  |  Rate limit: 30 req/s per IP, burst 10                     |    |
|  +---------^----------------------------------------------------+    |
|            |                                                        |
+------------+----------------------------------------------------------+
             |
     +-------+-------+
     |    Client      |
     |  (Port 80)     |
     +----------------+
```

**Services:**
- **Service A** (:3001) -- accepts client requests, forwards to B, receives callbacks from C
- **Service B** (:3002) -- receives from A, forwards to C
- **Service C** (:3003) -- receives from B, sends callback to A
- **Nginx** (:80) -- reverse proxy, only exposes Service A at `/service-a/*`

Only ports 80 and 22 are externally accessible.

## AWS Deployment (Production)

The production environment is deployed to AWS using a fully automated CI/CD pipeline.

```
Developer
    │
git push / merge to main
    │
GitHub
    │
AWS CodePipeline
    ├── Source   (GitHub via CodeConnections)
    ├── Build    (AWS CodeBuild)
    │       ├── runs test suite
    │       ├── builds Docker image
    │       ├── tags image with Git commit SHA  (e.g. devops-g8-driver-service:2670f56)
    │       ├── pushes to Amazon ECR
    │       └── generates imagedefinitions.json
    └── Deploy   (ECS rolling deployment)
            │
    Amazon ECS (Fargate)
            │
    Application Load Balancer (:80)
            │
         Client
```

**ECR repositories:**

| Service | Repository |
|---------|------------|
| booking-service | `devops-g8-booking-service` |
| driver-service | `devops-g8-driver-service` |
| tracking-service | `devops-g8-tracking-service` |

**Image tagging:** every build tags the image with the Git commit SHA rather than `latest`. This makes every deployment traceable and rollbacks deterministic -- you always know exactly which commit is running.

```
devops-g8-driver-service:2670f56   ✓ traceable
devops-g8-driver-service:latest    ✗ ambiguous
```

**Task definition revisions:** every successful deployment registers a new ECS task definition revision automatically. The ECS deploy action updates the service to the new revision; the previous revision remains available for rollback.

```
booking-service:  revision 8  → revision 9
driver-service:   revision 14 → revision 15
tracking-service: revision 10 → revision 11
```

**Deployment Circuit Breaker:** ECS Deployment Circuit Breaker is enabled on each service. If newly deployed tasks repeatedly fail their health checks, ECS automatically rolls back to the previous healthy task definition revision without manual intervention.

**Service Connect (internal networking):** driver-service and tracking-service are not exposed through the ALB. They communicate internally via ECS Service Connect using the `group8.internal` namespace. Services reference each other by FQDN (e.g. `http://tracking-service.group8.internal:3003`) -- the Service Connect sidecar resolves these names without any external DNS.

| Service | External | Internal hostname |
|---------|----------|-------------------|
| booking-service | via ALB at `/booking-service/*` | `booking-service.group8.internal:3001` |
| driver-service | not exposed | `driver-service.group8.internal:3002` |
| tracking-service | not exposed | `tracking-service.group8.internal:3003` |

**ALB endpoint:**
```
http://devops-g8-alb-1127437633.eu-west-3.elb.amazonaws.com
```

**Verify the deployment:**
```bash
# Health check through ALB
curl http://devops-g8-alb-1127437633.eu-west-3.elb.amazonaws.com/booking-service/health

# Full request flow
curl -X POST http://devops-g8-alb-1127437633.eu-west-3.elb.amazonaws.com/booking-service/request-ride \
  -H "Content-Type: application/json"
```

---

## Request Flow

1. Client -> `GET /service-a/greet-service-b` -> Nginx (:80)
2. Nginx strips prefix -> `http://service-a.internal:3001/greet-service-b`
3. Service A generates `X-Request-ID` (UUID) -> calls Service B `/greet`
4. Service B -> calls Service C `/greet-c`
5. Service C -> POSTs callback to Service A `/greeting-rcvd`
6. Service A resolves the pending request -> responds to client

## Service Discovery

Services communicate using hostnames rather than hardcoded IPs. Each service references its dependencies by name (e.g., `http://service-b.internal:3002`).

| Service | Hostname | Port |
|---------|----------|------|
| Service A | `service-a.internal` | 3001 |
| Service B | `service-b.internal` | 3002 |
| Service C | `service-c.internal` | 3003 |

**How it works:** The deploy script adds entries to `/etc/hosts` mapping each `.internal` hostname to `127.0.0.1`. When a service makes an HTTP request to `http://service-b.internal:3002`, the OS resolver reads `/etc/hosts` before querying DNS, resolving the name locally.

**What performs the resolution:** The Linux system resolver, configured via `/etc/nsswitch.conf` (`hosts: files dns`), checks `/etc/hosts` first. No external DNS server is involved.

**Troubleshooting discovery failures:**

```bash
grep '.internal' /etc/hosts                  # verify entries exist
getent hosts service-b.internal              # test resolution
grep hosts /etc/nsswitch.conf                # confirm "files" comes before "dns"
curl -v http://service-b.internal:3002/health  # test connectivity
```

If entries are missing, re-add them:
```bash
echo "127.0.0.1 service-b.internal" | sudo tee -a /etc/hosts
```

## Network Security

Services B and C are internal infrastructure -- they should only receive requests from other services on the same machine. Exposing them externally would bypass the Nginx reverse proxy and any access controls at that layer.

**Two layers enforce the protection:**

1. **UFW Firewall** -- only ports 22 (SSH) and 80 (HTTP) are open to external traffic. Ports 3001, 3002, and 3003 are blocked from outside the VM.
2. **Nginx routing** -- only `/service-a/*` paths are proxied. No routes exist for Service B or C.

**Verifying the protection:**

```bash
# From outside the VM -- these should fail/timeout:
curl http://<VM_PUBLIC_IP>:3002/health
curl http://<VM_PUBLIC_IP>:3003/health

# From outside the VM -- this should work:
curl http://<VM_PUBLIC_IP>/service-a/health

# Check firewall rules:
sudo ufw status verbose
```

**Troubleshooting connectivity issues:**

```bash
sudo ufw status                          # is the firewall active?
sudo ss -tlnp                            # which ports are listening?
curl http://service-b.internal:3002/health  # internal connectivity
sudo iptables -L -n --line-numbers       # check underlying rules
```

## Deploy

```bash
git clone <repository-url> ~/production-services
cd ~/production-services
sudo bash scripts/deploy.sh
```

This installs Node.js/Nginx, copies files to `/opt/production-services`, configures `/etc/hosts`, sets up systemd units, enables UFW, and starts everything.

For manual steps, see `scripts/deploy.sh` -- it's readable and commented.

## Operation

```bash
# Start (B and C first -- A depends on them)
sudo systemctl start service-b service-c && sleep 2 && sudo systemctl start service-a

# Stop (A first)
sudo systemctl stop service-a && sudo systemctl stop service-b service-c

# Restart
sudo systemctl restart service-b service-c && sleep 2 && sudo systemctl restart service-a

# Status
sudo systemctl status service-a service-b service-c nginx

# Health check
curl http://localhost/service-a/health

# Full flow test
curl http://localhost/service-a/greet-service-b

# Automated health monitoring (runs all checks, --watch for continuous)
sudo bash scripts/health-check.sh
```

## Logging

All services produce structured JSON logs to stdout, captured by the systemd journal.

Each log entry contains:

| Field | Description |
|-------|-------------|
| `timestamp` | ISO 8601 timestamp |
| `service` | Service name (`service-a`, `service-b`, `service-c`) |
| `event` | Event type (`request_received`, `request_forwarded`, `callback_received`, etc.) |
| `request_id` | UUID tracing the request across all services |
| `method` | HTTP method |
| `path` | Request path |
| `status` | HTTP status code |

**Viewing logs:**

```bash
sudo journalctl -u service-a                # all logs for a service
sudo journalctl -u service-a -f             # follow in real time
sudo journalctl -u service-a -u service-b -u service-c  # all services combined
```

Nginx logs: `/var/log/nginx/service-proxy-access.log` (JSON format), `/var/log/nginx/service-proxy-error.log`

Each service also exposes `GET /metrics` in Prometheus exposition format (request counts, error counts, request duration histogram, service up/down) -- see [Observability stack](#observability-stack-prometheus--grafana) below.

## Request Tracing

Every request is assigned an `X-Request-ID` (UUID). Service A generates this ID if one isn't provided by the client, then passes it via the `X-Request-ID` header to Service B, which forwards it to Service C. Service C includes it in the callback POST body back to Service A. Nginx also logs the header.

To trace a request end-to-end:

```bash
# 1. Trigger a request and note the request_id from the response
curl -s http://localhost/service-a/greet-service-b | python3 -m json.tool

# 2. Search all service logs for that ID
REQID="the-uuid-from-response"
sudo journalctl -u service-a -u service-b -u service-c --no-pager | grep "$REQID"

# 3. Check Nginx logs
grep "$REQID" /var/log/nginx/service-proxy-access.log
```

The `request_id` appears in: Nginx access log -> Service A (`request_received`, `request_forwarded`, `callback_received`) -> Service B (`request_received`, `request_forwarded`) -> Service C (`request_received`, `callback_sent`).

## Error Rate Alerting (Slack)

`scripts/error-alert-monitor.js` polls each service's `/metrics` endpoint on an interval, computes the **error rate over that interval** (not the cumulative rate since boot), and posts to Slack when it crosses a threshold. It runs continuously as its own process -- a Docker Compose service in the container deployment, or a systemd unit in the VM deployment -- and is the only thing in the repo that needs a Slack webhook.

**Why windowed, not cumulative:** the Prometheus-style counters (`http_requests_total`, `http_errors_total`) never reset, so `errors / requests` since boot would just decay toward a small number forever and never reflect "how bad is it right now." The monitor snapshots the previous poll and diffs against the current one each cycle instead.

**Metrics format:** `/metrics` is served in Prometheus text exposition format (see [Observability stack](#observability-stack-prometheus--grafana)), e.g. `http_requests_total{service="booking-service",method="POST",route="/request-ride",status_code="200"} 5`. The monitor sums `http_requests_total` and `http_errors_total` across all route/method/status label combinations for that service to get one total/failed count per poll -- it doesn't call the Prometheus server itself, it reads each service's raw `/metrics` output directly, the same way Prometheus's own scraper does.

### Setup

1. Create a Slack Incoming Webhook: `https://api.slack.com/apps` -> **Create New App** -> **From scratch** -> pick the exact workspace you'll actually be checking (if you have multiple workspaces with similar names, verify by team ID in the URL, e.g. `app.slack.com/client/T0XXXXXXX/...`, not just by display name) -> **Incoming Webhooks** -> activate -> **Add New Webhook to Workspace** -> pick a channel -> copy the URL.
2. Set `SLACK_WEBHOOK_URL` in `.env` (see `.env.example`). This file is gitignored -- never commit a real webhook URL.
3. Sanity-check the webhook directly before relying on it:
   ```bash
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"test"}' \
     "$SLACK_WEBHOOK_URL"
   ```
   A response of `ok` means Slack accepted it -- if nothing shows up in Slack afterward, you're looking at the wrong workspace or channel, not a broken webhook.

### Configuration

All variables are read from the environment; defaults apply if unset.

| Variable | Default | Description |
|----------|---------|--------------|
| `SLACK_WEBHOOK_URL` | *(required)* | Incoming Webhook URL to post alerts to |
| `SERVICES` | `booking-service`/`driver-service`/`tracking-service` via the old `service-a/b/c.internal` hostnames (matches the VM deployment's current wiring) | Comma-separated `name=metrics_url` pairs to monitor |
| `ERROR_THRESHOLD_PERCENT` | `20` | Error rate (%) that triggers an alert |
| `CHECK_INTERVAL_SECONDS` | `60` | How often to poll `/metrics` and evaluate the rate |
| `MIN_REQUESTS_SAMPLE` | `5` | Minimum requests in the interval before a rate is evaluated (avoids false alarms on low traffic, e.g. 1 failed out of 1 request = "100%") |
| `ALERT_COOLDOWN_SECONDS` | `900` | Minimum time between repeat alerts for the same service while a breach persists |
| `METRICS_TIMEOUT_MS` | `3000` | Timeout for each `/metrics` fetch |

**Note on naming:** the services were renamed `service-a/b/c` -> `booking-service`/`driver-service`/`tracking-service`, but that rename isn't complete everywhere yet -- `docker-compose.yml` (dev) and CI use the new names, while `docker-compose.prod.yml` and the systemd units still use the old ones. The monitor's `SERVICES` config always uses the new friendly names as labels in Slack messages regardless of environment, but points at whatever hostnames that environment's compose file or systemd wiring actually uses -- see `docker-compose.yml` vs `docker-compose.prod.yml` for the two different `SERVICES` values in use.

### Behavior

- **Breach:** error rate >= `ERROR_THRESHOLD_PERCENT` over the interval -> `:rotating_light:` alert with the service name, computed rate, and the raw `failed/total` counts for that window.
- **Recovery:** rate drops back below the threshold after a breach -> `:white_check_mark:` message, then it goes quiet again.
- **Cooldown:** a persisting breach re-alerts only after `ALERT_COOLDOWN_SECONDS`, not every interval.
- **Unreachable service:** if a `/metrics` fetch fails outright (service down, not just erroring), that's treated as its own breach (`:x:` outage alert) and recovers the same way once `/metrics` responds again.

### Where it runs

- **Docker Compose:** an `error-alert-monitor` service in `docker-compose.yml` / `docker-compose.prod.yml`, using the `node:20-alpine` image with the script mounted read-only, on the `backend` network. `SLACK_WEBHOOK_URL` is required (`${SLACK_WEBHOOK_URL:?...}`) -- Compose auto-loads it from a `.env` file in the project root, so `docker compose up` fails loudly if it's missing.
- **VM/systemd:** `systemd/error-alert-monitor.service`, same pattern as the other units, pulling `SLACK_WEBHOOK_URL` from `/opt/production-services/.env` via `EnvironmentFile=`.

### Verifying it

```bash
# 1. Confirm a clean baseline (0% error rate) with normal traffic
curl -X POST http://localhost:8080/booking-service/request-ride

# 2. Force real failures
docker compose stop driver-service
for i in {1..8}; do curl -s -X POST http://localhost:8080/booking-service/request-ride > /dev/null; done

# 3. Check Slack for the alert(s), then recover
docker compose start driver-service
curl -X POST http://localhost:8080/booking-service/request-ride
# Check Slack again for the recovery message
```

## Systemd

- **Dependency order:** A starts `After` B and C, and `Wants` them as soft dependencies -- systemd starts B and C first if not already running, but A is not forced down if one later stops. A detects an unreachable dependency in its own request handling and returns a 502, rather than relying on systemd to take it down.
- **Auto-restart:** `Restart=on-failure`, `RestartSec=3`
- **Boot persistence:** All services enabled via `systemctl enable`, start automatically on boot.

## Troubleshooting

For any service issue, the general approach is: `systemctl status <svc>` -> `journalctl -u <svc>` -> restart in dependency order.

**Service startup failures:**
```bash
sudo systemctl status service-a
sudo journalctl -u service-a -n 50 --no-pager
# Common causes: Node.js not installed (which node), missing node_modules,
# port conflict (sudo ss -tlnp | grep 3001)
```

**Service dependency failures:**
```bash
# If service-a won't start, check its dependencies first
sudo systemctl status service-b service-c
# Restart in order
sudo systemctl restart service-b service-c && sleep 2 && sudo systemctl restart service-a
```

**Reverse proxy failures:**
```bash
sudo nginx -t                              # config syntax check
sudo systemctl status nginx
ls -la /etc/nginx/sites-enabled/           # verify config is linked
sudo tail -20 /var/log/nginx/service-proxy-error.log
# Compare direct vs proxied:
curl http://service-a.internal:3001/health   # direct
curl http://localhost/service-a/health       # via Nginx
```

**Service discovery / name resolution failures:**
```bash
grep '.internal' /etc/hosts                # entries exist?
getent hosts service-b.internal            # resolution works?
grep hosts /etc/nsswitch.conf              # "files" before "dns"?
# If entries are missing, re-add and restart services
```

**Network access failures:**
```bash
sudo ufw status verbose                    # firewall active and rules correct?
sudo ss -tlnp | grep <port>               # service bound to correct interface?
# Should show 0.0.0.0:<port> or 127.0.0.1:<port>
```

**Missing logs:**
```bash
sudo journalctl -u service-a --since "5 minutes ago"  # journal receiving logs?
sudo journalctl -u service-a -f            # follow and trigger a request to verify
sudo journalctl --disk-usage               # check journal isn't full
```

**Invalid routing behavior:**
```bash
curl -v http://localhost/service-a/health   # check Nginx routes correctly
# Verify proxy_pass strips the /service-a prefix:
# /service-a/health should reach service-a at /health
curl http://localhost/service-a/service-a/health  # should 404 (path duplication check)
cat /etc/nginx/sites-enabled/service-proxy
```

**Inter-service communication failures:**
```bash
# Test each link in the chain
curl http://service-a.internal:3001/health
curl http://service-b.internal:3002/health
curl http://service-c.internal:3003/health
# Test the forward path manually
curl -H "X-Request-ID: test-123" http://service-b.internal:3002/greet
curl -H "X-Request-ID: test-123" http://service-c.internal:3003/greet-c
```

## Running with Docker Compose

The same production flow can run in Docker Compose instead of on a VM with systemd.

### Known issue: image builds may need host networking

On some hosts, `docker compose build` (or `up --build`) fails with `npm error Exit handler never called!` after about two minutes, caused by DNS resolution failures (`EAI_AGAIN`) inside the build container. This happens when Docker's bridge networks don't have working NAT rules -- commonly because `/etc/docker/daemon.json` has `"iptables": false` set (e.g. as a workaround for a Multipass/Docker iptables conflict on the same host).

**If you hit this**, check:
```bash
cat /etc/docker/daemon.json
```
If `"iptables": false` is set, change it to `true` and restart Docker:
```bash
sudo sed -i 's/"iptables": false/"iptables": true/' /etc/docker/daemon.json
sudo systemctl restart docker
```

If builds still fail after that (container DNS can still be broken even with NAT rules present, e.g. due to conntrack issues), build each image directly with host networking, which bypasses the bridge entirely for the build step only:
```bash
docker build --network=host --no-cache -t devops-production-style-service-environment-booking-service ./services/booking-service -f services/Dockerfile
docker build --network=host --no-cache -t devops-production-style-service-environment-service-b ./services/service-b -f services/Dockerfile
docker build --network=host --no-cache -t devops-production-style-service-environment-service-c ./services/service-c -f services/Dockerfile
```
Then start normally -- runtime networking is unaffected, only the build step needed this:
```bash
docker compose up -d
```

### Start the system

`SLACK_WEBHOOK_URL` is required (the `error-alert-monitor` service needs it) -- make sure it's set in a `.env` file at the project root first; Compose loads it automatically. See [Error Rate Alerting](#error-rate-alerting-slack) for how to get one.

```bash
docker compose up --build -d
```

**Expected output** (after a successful build, or after building manually per above):
```
Container nginx                  Started
Container booking-service        Started
Container driver-service         Started
Container tracking-service       Started
Container prometheus             Started
Container grafana                Started
Container error-alert-monitor    Started
```

Confirm all seven are running:
```bash
docker compose ps
```
Expected: all seven containers (`nginx`, `booking-service`, `driver-service`, `tracking-service`, `prometheus`, `grafana`, `error-alert-monitor`) show `Up`.

### Test the public route

```bash
curl -i http://localhost:8080/booking-service/health
```
Expected:
```
HTTP/1.1 200 OK
{"service":"booking-service","status":"healthy","port":"3001","message":"booking-service listening on 3001"}
```

Full request flow (A -> B -> C -> A callback):
```bash
curl -i -X POST http://localhost:8080/booking-service/request-ride \
  -H "Content-Type: application/json"
```
Expected:
```
HTTP/1.1 200 OK
{"request_id":"<generated-uuid>","status":"success","message":"Request completed successfully"}
```

### Prove B and C are internal

From the host, these should fail immediately (connection refused):
```bash
curl -i --connect-timeout 3 http://localhost:3002/health
curl -i --connect-timeout 3 http://localhost:3003/health
```
Expected:
```
curl: (7) Failed to connect to localhost port 3002 after 0 ms: Couldn't connect to server
curl: (7) Failed to connect to localhost port 3003 after 0 ms: Couldn't connect to server
```

From inside the Docker network, they work. Note: the `node:20-alpine` images don't include `curl`, so use `wget`:
```bash
docker compose exec booking-service wget -qO- http://driver-service:3002/health
docker compose exec service-b wget -qO- http://service-c:3003/health
```
Expected:
```
{"service":"service-b","status":"healthy","port":"3002", ...}
{"service":"service-c","status":"healthy","port":"3003", ...}
```

### View logs

```bash
docker compose logs                  # all services
docker compose logs booking-service        # single service
docker compose logs nginx            # Nginx access/error logs
```

### Observability stack (Prometheus + Grafana)

Every service exposes Prometheus-compatible metrics at `GET /metrics` (`http_requests_total`,
`http_errors_total`, `http_request_duration_seconds`, `service_up`), scraped every 5s using
Docker Compose service names (see [prometheus.yml](prometheus.yml) -- no hardcoded `localhost`).

**Access:**

| Tool | URL | Notes |
|------|-----|-------|
| Prometheus | http://localhost:9090 | Query metrics, check scrape target health |
| Grafana | http://localhost:3000 | Login `admin` / `admin`, or browse anonymously (Viewer) |

**View raw metrics from a service:**

```bash
curl http://localhost:8080/booking-service/metrics
docker compose exec booking-service wget -qO- http://driver-service:3002/metrics
```

**Confirm Prometheus is scraping all services:**

```bash
open http://localhost:9090/targets
```

Expected: `prometheus`, `service-a`, `service-b`, and `service-c` targets all show `UP`.

**View the central operating dashboard:**

```bash
open http://localhost:3000/d/operating-view
```

The "Central Operating View" dashboard is auto-provisioned from
[grafana/dashboards/operating-view.json](grafana/dashboards/operating-view.json) (datasource
config in [grafana/provisioning/](grafana/provisioning/)) and shows:

- Service up/down status (`up{job=~"booking-service|driver-service|tracking-service"}`)
- Request rate per service (`rate(http_requests_total[1m])`)
- Error rate % per service (`http_errors_total` / `http_requests_total`)
- p95 latency per service (`histogram_quantile(0.95, ...http_request_duration_seconds_bucket...)`)
- Alert state (populated once alert rules are added to Prometheus)

Slack notifications for a sustained high error rate don't depend on Prometheus/Grafana at all -- they come from a separate lightweight poller reading each service's raw `/metrics` directly; see [Error Rate Alerting](#error-rate-alerting-slack).

Send some traffic and refresh the dashboard to see the panels move:

```bash
for i in $(seq 1 20); do curl -s -o /dev/null -X POST http://localhost:8080/booking-service/request-ride; done
```

### Trace a request

```bash
curl -i -X POST http://localhost:8080/booking-service/request-ride \
  -H "X-Request-ID: demo-container-001" \
  -H "Content-Type: application/json"
docker compose logs | grep demo-container-001
```
Expected: the same `request_id` appears in Service A (`request_received`, `request_forwarded`, `callback_received`), Service B (`request_received`, `request_forwarded`), and Service C (`request_received`, `callback_sent`), in that order.

### Stop a service and observe failure, then recover

```bash
docker compose stop service-b
curl -i -X POST http://localhost:8080/booking-service/request-ride \
  -H "X-Request-ID: fail-test-001" \
  -H "Content-Type: application/json"
```
Expected:
```
HTTP/1.1 502 Bad Gateway
{"request_id":"fail-test-001","status":"error","message":"Failed to reach service-b"}
```
Service A's logs record the failure:
```bash
docker compose logs booking-service | grep fail-test-001
```
Expected: a `request_failed` log entry with `"status":502`.

Recover:
```bash
docker compose start service-b
curl -i -X POST http://localhost:8080/booking-service/request-ride \
  -H "X-Request-ID: recovery-test-001" \
  -H "Content-Type: application/json"
```
Expected: `200 OK` with a success message -- the system recovers automatically once Service B is back up.


## Distributed Tracing (Jaeger)

All three services are instrumented with OpenTelemetry. Every HTTP request is traced end-to-end across the full booking-service -> driver-service -> tracking-service -> booking-service(callback) chain.

**Access Jaeger UI:**
```
http://localhost:16686
```

**Confirm all three services are sending traces:**
```bash
curl -s http://localhost:16686/api/services | python3 -m json.tool
```
Expected: `booking-service`, `driver-service`, and `tracking-service` all listed.

**View a ride booking trace:**
```bash
curl -s -X POST http://localhost:8080/booking-service/request-ride \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: demo-ride-001" \
  -d '{"pickup": "Westlands", "dropoff": "CBD"}' | python3 -m json.tool
```
Then open http://localhost:16686, select `booking-service`, click Find Traces.
Click the `POST /request-ride` trace to see the full waterfall -- every hop
across all three services with exact timing per span.

**What the scatter plot shows:**
Each dot is one request. Y-axis = duration, X-axis = time. Bigger dots took
longer. A cluster of dots shooting upward means something slowed down.

**What a trace looks like:**
```
booking-service: POST /request-ride          [total: ~8ms]
  |
  +-- calls driver-service                   [~1ms]
        |
        +-- driver-service: POST /assign-driver    [~5ms]
              |
              +-- calls tracking-service           [~1ms]
                    |
                    +-- tracking-service: POST /start-tracking  [~3ms]
                          |
                          +-- calls back booking-service        [~1ms]
```

---

## Advanced Health Endpoints

Each service checks its downstream dependency before reporting healthy.
booking-service pings driver-service, driver-service pings tracking-service.
tracking-service has no dependencies so it always reports healthy.

If driver-service is unreachable, booking-service reports `degraded` -- not
`healthy`. This lets load balancers and monitoring systems detect the real
problem immediately instead of sending traffic to a service that will fail anyway.

**Normal state:**
```bash
curl -s http://localhost:8080/booking-service/health | python3 -m json.tool
```
```json
{
    "service": "booking-service",
    "status": "healthy",
    "dependencies": {
        "driver-service": "ok"
    }
}
```

**Degraded state -- stop driver-service:**
```bash
docker compose stop driver-service
curl -s http://localhost:8080/booking-service/health | python3 -m json.tool
```
```json
{
    "service": "booking-service",
    "status": "degraded",
    "dependencies": {
        "driver-service": "unreachable"
    }
}
```
HTTP status also changes from 200 to 207 when degraded.

**Recover:**
```bash
docker compose start driver-service
```

---

## Failure Demo Endpoints

Each service has `/slow` and `/fail` endpoints for testing the observability
stack. All responses include `"note": "lab-only"`.

| Endpoint | Simulates |
|----------|-----------|
| `GET /slow?ms=N` | GPS lag, slow DB query, network congestion |
| `GET /fail` | Payment declined, third-party API down |

**Test slow endpoint (latency spike in Grafana):**
```bash
curl -i "http://localhost:8080/booking-service/slow?ms=1000"
```
Expected: HTTP 200 after 1 second delay. Watch p95 Latency panel spike in Grafana.

**Test fail endpoint (error rate in Grafana):**
```bash
curl -i http://localhost:8080/booking-service/fail
```
Expected: HTTP 500 with `"message": "Payment declined"`.

**Generate a visible error rate on the dashboard:**
```bash
for i in $(seq 1 20); do
  curl -s http://localhost:8080/booking-service/fail > /dev/null
  curl -s -X POST http://localhost:8080/booking-service/request-ride \
    -H "Content-Type: application/json" \
    -d '{"pickup": "Westlands", "dropoff": "CBD"}' > /dev/null
done
```
This produces ~50% error rate on the Grafana Error Rate panel.

**Test on internal services (not exposed through Nginx):**
```bash
docker compose exec booking-service wget -qO- "http://driver-service:3002/slow?ms=1000"
docker compose exec booking-service wget -qO- http://tracking-service:3003/fail
```

**Full observability test sequence:**
```bash
# Normal ride bookings (baseline)
for i in $(seq 1 10); do
  curl -s -X POST http://localhost:8080/booking-service/request-ride \
    -H "Content-Type: application/json" \
    -d '{"pickup": "Westlands", "dropoff": "CBD"}' > /dev/null
done

# Introduce errors (watch error rate climb in Grafana)
for i in $(seq 1 10); do
  curl -s http://localhost:8080/booking-service/fail > /dev/null
done

# Introduce latency (watch p95 latency spike in Grafana)
curl -s "http://localhost:8080/booking-service/slow?ms=3000" > /dev/null

# Stop driver-service (watch dashboard go RED in Grafana)
docker compose stop driver-service
sleep 15
curl -s http://localhost:8080/booking-service/health | python3 -m json.tool

# Recover (watch dashboard go GREEN)
docker compose start driver-service

# Open Jaeger to see all traces from above
# http://localhost:16686 -> booking-service -> Find Traces
```
