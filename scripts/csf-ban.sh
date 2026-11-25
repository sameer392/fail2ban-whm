#!/bin/bash
# Fail2Ban ban action: queues the ban for scripts/f2b-ban-worker.sh and returns at once.
# All the slow work (domain lookup, country/org check, ipset, csf -d, email) happens in the
# worker, so a burst of bans does not stall fail2ban's detection of further IPs.
# Usage: csf-ban.sh <ip> <jail_name>
IP="$1"
JAIL="$2"
[ -z "$IP" ] || [ -z "$JAIL" ] && exit 1
SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/f2b-queue.sh"
f2b_queue_push ban "$JAIL" "$IP"
exit 0
