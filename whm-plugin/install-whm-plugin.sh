#!/bin/bash
# Install Fail2Ban Manager WHM plugin
# Run as root. Must be run from the whm-plugin directory.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/plugin"

[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }
[ ! -f "$PLUGIN_DIR/index.php" ] && { echo "Plugin files not found. Run from whm-plugin directory."; exit 1; }

echo "=== Installing Fail2Ban Manager WHM plugin ==="

mkdir -p /var/cpanel/apps
mkdir -p /usr/local/cpanel/whostmgr/docroot/cgi/fail2ban_manager
mkdir -p /usr/local/cpanel/whostmgr/docroot/addon_plugins

cp -f "$PLUGIN_DIR/index.php" /usr/local/cpanel/whostmgr/docroot/cgi/fail2ban_manager/
cp -f "$PLUGIN_DIR/fail2ban_manager.png" /usr/local/cpanel/whostmgr/docroot/cgi/fail2ban_manager/
chmod 755 /usr/local/cpanel/whostmgr/docroot/cgi/fail2ban_manager/index.php

cp -f "$PLUGIN_DIR/fail2ban_manager.png" /usr/local/cpanel/whostmgr/docroot/addon_plugins/
chmod 644 /usr/local/cpanel/whostmgr/docroot/addon_plugins/fail2ban_manager.png

/usr/local/cpanel/bin/register_appconfig "$PLUGIN_DIR/fail2ban_manager.conf"

echo ""
echo "Plugin installed. Fail2Ban Manager should appear in WHM."
echo "(No cPanel restart needed - refresh WHM if the plugin does not appear.)"
