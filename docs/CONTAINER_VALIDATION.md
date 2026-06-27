# Container Validation Evidence

Validation tests for the Docker Compose deployment, following the lab assignment requirements.

## 1. Start the system

```bash
docker compose up --build -d
```

Expected output:
```
[+] Building ...
[+] Running 4/4
 ✔ Container devops-production-style-service-environment-service-c-1  Started
 ✔ Container devops-production-style-service-environment-service-b-1  Started
 ✔ Container devops-production-style-service-environment-service-a-1  Started
 ✔ Container devops-production-style-service-environment-nginx-1      Started
```

## 2. Confirm containers are running

```bash
docker compose ps
```

Expected: all four containers (nginx, service-a, service-b, service-c) show status "Up".

## 3. Test public entry point

```bash
curl -i http://localhost:8080/service-a/health
```

Expected: HTTP 200 with JSON response showing service-a is healthy.

```bash
curl -i -X POST http://localhost:8080/service-a/greet-service-b
```

Expected: HTTP 200 with `"status":"success"`, confirming the full A -> B -> C -> A callback flow works through Nginx.

## 4. Prove B and C are not directly exposed

```bash
curl -i --connect-timeout 3 http://localhost:3002/health
curl -i --connect-timeout 3 http://localhost:3003/health
```

Expected: connection refused or timeout. Services B and C do not publish host ports — they are only reachable inside the Docker Compose network.

## 5. Prove internal service discovery works

```bash
docker compose exec service-a curl -i http://service-b:3002/health
docker compose exec service-b curl -i http://service-c:3003/health
```

Expected: HTTP 200 from each. Docker Compose DNS resolves service names to the correct container IPs within the internal network.

## 6. Trace one request

Send a request with a known request ID:

```bash
curl -i -X POST http://localhost:8080/service-a/greet-service-b \
  -H "X-Request-ID: demo-container-001"
```

Then check logs:

```bash
docker compose logs | grep demo-container-001
```

Expected: the request ID `demo-container-001` appears in service-a, service-b, service-c, and nginx logs, proving end-to-end tracing works.

## 7. Stop Service B and observe failure

Stop service-b:

```bash
docker compose stop service-b
```

Send the request again:

```bash
curl -i -X POST http://localhost:8080/service-a/greet-service-b \
  -H "X-Request-ID: fail-service-b-001"
```

Expected: HTTP 502 response from service-a with `"message":"Failed to reach service-b"`. Service-a logs the failure with the request ID.

Check logs:

```bash
docker compose logs service-a | grep fail-service-b-001
```

Expected: log entry showing `"event":"request_failed"` with the request ID.

Recover:

```bash
docker compose start service-b
```

Send the request again:

```bash
curl -i -X POST http://localhost:8080/service-a/greet-service-b \
  -H "X-Request-ID: recovery-001"
```

Expected: HTTP 200 with `"status":"success"` — the system recovers after service-b is restarted.
