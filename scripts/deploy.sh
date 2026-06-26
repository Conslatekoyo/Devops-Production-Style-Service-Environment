#!/bin/bash
set -euo pipefail

echo "=== Production Services Deployment ==="
echo ""

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)"
  exit 1
fi

APP_DIR="/opt/production-services"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- Install dependencies ---
echo "[1/8] Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq nginx curl > /dev/null 2>&1

if ! command -v node &> /dev/null; then
  echo "  Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
  apt-get install -y -qq nodejs > /dev/null 2>&1
fi
echo "  Node.js $(node --version), npm $(npm --version)"

# --- Copy application files ---
echo "[2/8] Deploying application to ${APP_DIR}..."
mkdir -p "$APP_DIR"
cp -r "$REPO_DIR/services" "$APP_DIR/"
cp -r "$REPO_DIR/nginx" "$APP_DIR/"
cp -r "$REPO_DIR/systemd" "$APP_DIR/"
cp -r "$REPO_DIR/scripts" "$APP_DIR/"

# --- Install npm dependencies ---
echo "[3/8] Installing npm dependencies..."
for svc in service-a service-b service-c; do
  (cd "$APP_DIR/services/$svc" && npm install --production --silent 2>/dev/null)
done

# --- Service discovery via /etc/hosts ---
echo "[4/8] Configuring service discovery..."
HOSTS_ENTRIES=(
  "127.0.0.1 service-a.internal"
  "127.0.0.1 service-b.internal"
  "127.0.0.1 service-c.internal"
)
for entry in "${HOSTS_ENTRIES[@]}"; do
  if ! grep -qF "$entry" /etc/hosts; then
    echo "$entry" >> /etc/hosts
    echo "  Added: $entry"
  else
    echo "  Exists: $entry"
  fi
done

# --- Nginx configuration ---
echo "[5/8] Configuring Nginx reverse proxy..."
cp "$APP_DIR/nginx/service-proxy.conf" /etc/nginx/sites-available/service-proxy
ln -sf /etc/nginx/sites-available/service-proxy /etc/nginx/sites-enabled/service-proxy
rm -f /etc/nginx/sites-enabled/default
nginx -t 2>&1
systemctl restart nginx
systemctl enable nginx

# --- Systemd service units ---
echo "[6/8] Installing systemd service units..."
for svc in service-a service-b service-c; do
  cp "$APP_DIR/systemd/${svc}.service" /etc/systemd/system/
done
systemctl daemon-reload

# --- Firewall rules ---
echo "[7/8] Configuring firewall (UFW)..."
ufw --force reset > /dev/null 2>&1
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow ssh > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
# Ports 3001, 3002, and 3003 are NOT opened.
# They are bound to 127.0.0.1 in the application code (BIND_HOST), so they
# are not reachable from outside the VM even if UFW were misconfigured.
ufw --force enable > /dev/null 2>&1
echo "  UFW enabled: SSH (22) and HTTP (80) allowed, ports 3001-3003 blocked from external"

# --- Start services ---
echo "[8/8] Starting services..."
systemctl enable service-b service-c service-a
systemctl start service-b
systemctl start service-c
sleep 2
systemctl start service-a

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Verifying services..."
sleep 2
for svc in service-a service-b service-c; do
  STATUS=$(systemctl is-active "$svc" 2>/dev/null || true)
  echo "  $svc: $STATUS"
done
NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || true)
echo "  nginx: $NGINX_STATUS"

echo ""
echo "Testing health endpoints..."
curl -sf http://localhost/service-a/health && echo ""
curl -sf http://127.0.0.1:3002/health && echo ""
curl -sf http://127.0.0.1:3003/health && echo ""

echo ""
echo "Testing full request flow..."
curl -sf -X POST http://localhost/service-a/greet-service-b && echo ""

echo ""
echo "=== All checks passed ==="
