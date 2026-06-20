# Production Service Environment

Three internal HTTP services orchestrated with Nginx, systemd, and Linux networking on Ubuntu.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Ubuntu VM                                   │
│                                                                     │
│  ┌──────────────┐    ┌─────────────────────────────────────────┐    │
│  │   UFW        │    │        Internal Network (127.0.0.1)     │    │
│  │   Firewall   │    │                                         │    │
│  │              │    │  ┌───────────┐      ┌───────────┐       │    │
│  │  Allow:      │    │  │ Service B │◄─────│ Service A │       │    │
│  │   22 (SSH)   │    │  │  :3002    │      │  :3001    │◄──┐   │    │
│  │   80 (HTTP)  │    │  │ /greet    │      │ /greet-   │   │   │    │
│  │              │    │  │ /health   │      │  service-b│   │   │    │
│  │  Block:      │    │  │ /metrics  │      │ /greeting-│   │   │    │
│  │   3001       │    │  └─────┬─────┘      │  rcvd     │   │   │    │
│  │   3002       │    │        │             │ /health   │   │   │    │
│  │   3003       │    │        │             │ /metrics  │   │   │    │
│  │              │    │        ▼             └─────▲─────┘   │   │    │
│  │              │    │  ┌───────────┐            │          │   │    │
│  │              │    │  │ Service C │────────────┘          │   │    │
│  │              │    │  │  :3003    │  callback POST        │   │    │
│  │              │    │  │ /greet-c  │  /greeting-rcvd       │   │    │
│  │              │    │  │ /health   │                       │   │    │
│  │              │    │  │ /metrics  │                       │   │    │
│  │              │    │  └───────────┘                       │   │    │
│  │              │    └─────────────────────────────────────────┘    │
│  └──────┬───────┘                                           │      │
│         │                                                   │      │
│  ┌──────▼───────────────────────────────────────────────────┘─┐    │
│  │                    Nginx (:80)                              │    │
│  │  /service-a/*  →  proxy_pass service-a.internal:3001       │    │
│  │  /*            →  404                                       │    │
│  │  Rate limit: 30 req/s per IP, burst 10                     │    │
│  └─────────▲──────────────────────────────────────────────────┘    │
│            │                                                        │
└────────────┼────────────────────────────────────────────────────────┘
             │
     ┌───────┴───────┐
     │    Client      │
     │  (Port 80)     │
     └───────────────┘
```

**Services:**
- **Service A** (:3001) — accepts client requests, forwards to B, receives callbacks from C
- **Service B** (:3002) — receives from A, forwards to C
- **Service C** (:3003) — receives from B, sends callback to A
- **Nginx** (:80) — reverse proxy, only exposes Service A at `/service-a/*`

Only ports 80 and 22 are externally accessible.

## Request Flow

1. Client → `GET /service-a/greet-service-b` → Nginx (:80)
2. Nginx strips prefix → `http://service-a.internal:3001/greet-service-b`
3. Service A generates `X-Request-ID` (UUID) → calls Service B `/greet`
4. Service B → calls Service C `/greet-c`
5. Service C → POSTs callback to Service A `/greeting-rcvd`
6. Service A resolves the pending request → responds to client

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

Services B and C are internal infrastructure — they should only receive requests from other services on the same machine. Exposing them externally would bypass the Nginx reverse proxy and any access controls at that layer.

**Two layers enforce the protection:**

1. **UFW Firewall** — only ports 22 (SSH) and 80 (HTTP) are open to external traffic. Ports 3001, 3002, and 3003 are blocked from outside the VM.
2. **Nginx routing** — only `/service-a/*` paths are proxied. No routes exist for Service B or C.

**Verifying the protection:**

```bash
# From outside the VM — these should fail/timeout:
curl http://<VM_PUBLIC_IP>:3002/health
curl http://<VM_PUBLIC_IP>:3003/health

# From outside the VM — this should work:
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

For manual steps, see `scripts/deploy.sh` — it's readable and commented.

## Operation

```bash
# Start (B and C first — A depends on them)
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

Each service also exposes `GET /metrics` with counters (uptime, request counts, status codes, response times).

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

The `request_id` appears in: Nginx access log → Service A (`request_received`, `request_forwarded`, `callback_received`) → Service B (`request_received`, `request_forwarded`) → Service C (`request_received`, `callback_sent`).

## Systemd

- **Dependency order:** A `Requires` and starts `After` B and C. If B or C stops, A stops too.
- **Auto-restart:** `Restart=on-failure`, `RestartSec=3`
- **Boot persistence:** All services enabled via `systemctl enable`, start automatically on boot.

## Troubleshooting

For any service issue, the general approach is: `systemctl status <svc>` → `journalctl -u <svc>` → restart in dependency order.

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

## Uninstall

```bash
sudo bash scripts/uninstall.sh
```

Removes all services, Nginx config, `/etc/hosts` entries, firewall rules, and application files.
