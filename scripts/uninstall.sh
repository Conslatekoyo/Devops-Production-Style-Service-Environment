#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)"
  exit 1
fi

echo "=== Uninstalling Production Services ==="

echo "Stopping services..."
for svc in service-a service-b service-c; do
  systemctl stop "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
  rm -f "/etc/systemd/system/${svc}.service"
done
systemctl daemon-reload

echo "Removing Nginx config..."
rm -f /etc/nginx/sites-enabled/service-proxy
rm -f /etc/nginx/sites-available/service-proxy
systemctl restart nginx 2>/dev/null || true

echo "Cleaning /etc/hosts..."
sed -i '/service-a\.internal/d' /etc/hosts
sed -i '/service-b\.internal/d' /etc/hosts
sed -i '/service-c\.internal/d' /etc/hosts

echo "Removing application files..."
rm -rf /opt/production-services

echo "Resetting firewall..."
ufw --force reset > /dev/null 2>&1

echo "=== Uninstall complete ==="
