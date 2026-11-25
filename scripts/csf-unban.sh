#!/bin/bash
# Fail2Ban unban action: queues the unban for scripts/f2b-ban-worker.sh.
# Usage: csf-unban.sh <ip>
IP="$1"
[ -z "$IP" ] && exit 1
SCRIPT_DIR="$(dirname "$0")"
. "${SCRIPT_DIR}/f2b-queue.sh"
f2b_queue_push unban - "$IP"
exit 0
