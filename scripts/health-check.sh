#!/bin/bash
# Health monitoring script — checks all services and reports status
# Usage: sudo bash scripts/health-check.sh
#   Run with --watch to continuously monitor (every 10 seconds)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

check_service() {
  local name=$1
  local url=$2
  local response
  local http_code

  http_code=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 3 "$url" 2>/dev/null)
  if [ "$http_code" = "200" ]; then
    echo -e "  ${GREEN}✓${NC} $name ($url) — HTTP $http_code"
    return 0
  else
    echo -e "  ${RED}✗${NC} $name ($url) — HTTP ${http_code:-timeout}"
    return 1
  fi
}

check_systemd() {
  local name=$1
  local status
  status=$(systemctl is-active "$name" 2>/dev/null)
  if [ "$status" = "active" ]; then
    echo -e "  ${GREEN}✓${NC} $name systemd unit — $status"
    return 0
  else
    echo -e "  ${RED}✗${NC} $name systemd unit — ${status:-not found}"
    return 1
  fi
}

run_checks() {
  local failures=0

  echo "=== System Health Check — $(date -Iseconds) ==="
  echo ""

  echo "Systemd Units:"
  check_systemd "service-a" || ((failures++))
  check_systemd "service-b" || ((failures++))
  check_systemd "service-c" || ((failures++))
  check_systemd "nginx"     || ((failures++))
  echo ""

  echo "Health Endpoints:"
  check_service "Service A (via Nginx)" "http://localhost/service-a/health" || ((failures++))
  check_service "Service B (direct)"    "http://service-b.internal:3002/health" || ((failures++))
  check_service "Service C (direct)"    "http://service-c.internal:3003/health" || ((failures++))
  echo ""

  echo "Full Flow Test:"
  local flow_response
  flow_response=$(curl -sf --max-time 15 "http://localhost/service-a/greet-service-b" 2>/dev/null)
  if echo "$flow_response" | grep -q '"status":"success"'; then
    local req_id
    req_id=$(echo "$flow_response" | python3 -c "import sys,json; print(json.load(sys.stdin)['request_id'])" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} Full request flow — OK (request_id: $req_id)"
  else
    echo -e "  ${RED}✗${NC} Full request flow — FAILED"
    ((failures++))
  fi
  echo ""

  echo "Metrics:"
  for svc in service-a:3001 service-b:3002 service-c:3003; do
    local name=${svc%:*}
    local port=${svc#*:}
    local metrics_resp
    metrics_resp=$(curl -sf --max-time 3 "http://localhost:$port/metrics" 2>/dev/null)
    if [ -n "$metrics_resp" ]; then
      local uptime reqs
      uptime=$(echo "$metrics_resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['uptime_seconds'])" 2>/dev/null)
      reqs=$(echo "$metrics_resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['requests_total'])" 2>/dev/null)
      echo -e "  ${GREEN}✓${NC} $name — uptime: ${uptime}s, requests: $reqs"
    else
      echo -e "  ${YELLOW}?${NC} $name — metrics unavailable"
    fi
  done
  echo ""

  echo "Firewall:"
  if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    echo -e "  ${GREEN}✓${NC} UFW is active"
  else
    echo -e "  ${YELLOW}!${NC} UFW is not active"
  fi

  echo "DNS Resolution:"
  for host in service-a.internal service-b.internal service-c.internal; do
    if getent hosts "$host" > /dev/null 2>&1; then
      echo -e "  ${GREEN}✓${NC} $host resolves"
    else
      echo -e "  ${RED}✗${NC} $host does not resolve"
      ((failures++))
    fi
  done
  echo ""

  if [ $failures -eq 0 ]; then
    echo -e "${GREEN}All checks passed.${NC}"
  else
    echo -e "${RED}$failures check(s) failed.${NC}"
  fi
  echo ""
  return $failures
}

if [ "$1" = "--watch" ]; then
  while true; do
    clear
    run_checks
    sleep 10
  done
else
  run_checks
fi
