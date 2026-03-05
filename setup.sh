#!/bin/bash
#
# Fail2Ban WordPress wp-login - Setup script (config deploy only)
# Use when fail2ban is already installed. Copies config and restarts.
# Must be run as root
#

set -e

CONFIG_DIR="/root/fail2ban"

# Check root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" >&2
   exit 1
fi

# Check fail2ban is installed
if ! rpm -q fail2ban-server &>/dev/null; then
   echo "fail2ban is not installed. Run ./install.sh for full installation." >&2
   exit 1
fi

echo "=== Fail2Ban WordPress wp-login - Setup (config deploy) ==="
echo

echo "[1/2] Deploying config to /etc/fail2ban/..."
cp -f "$CONFIG_DIR/filter.d/"*.conf /etc/fail2ban/filter.d/
cp -f "$CONFIG_DIR/jail.d/"*.conf /etc/fail2ban/jail.d/
[ -f "$CONFIG_DIR/action.d/csf-domain.conf" ] && cp -f "$CONFIG_DIR/action.d/csf-domain.conf" /etc/fail2ban/action.d/
[ -f "$CONFIG_DIR/fail2ban.d/loglevel-verbose.conf" ] && cp -f "$CONFIG_DIR/fail2ban.d/loglevel-verbose.conf" /etc/fail2ban/fail2ban.d/
mkdir -p /etc/fail2ban/scripts
[ -f "$CONFIG_DIR/scripts/csf-ban.sh" ] && cp -f "$CONFIG_DIR/scripts/csf-ban.sh" /etc/fail2ban/scripts/ && chmod +x /etc/fail2ban/scripts/csf-ban.sh
echo "      Config deployed."

echo "[2/2] Restarting fail2ban..."
systemctl restart fail2ban
# Wait for fail2ban socket to be ready (avoid "Failed to access socket" on quick re-runs)
for i in {1..10}; do
    fail2ban-client status &>/dev/null && break
    sleep 1
done
echo "      Done."

echo
fail2ban-client status
echo
echo "=== Setup complete ==="
