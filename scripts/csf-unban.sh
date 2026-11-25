#!/bin/bash
# Fail2Ban unban helper: removes the IP from the ipset fast block and from CSF's deny list.
# Usage: csf-unban.sh <ip>
IP="$1"
[ -z "$IP" ] && exit 1
SCRIPT_DIR="$(dirname "$0")"
[ -f "${SCRIPT_DIR}/f2b-ipset.sh" ] && . "${SCRIPT_DIR}/f2b-ipset.sh" && f2b_ipset_del "$IP"
/usr/sbin/csf -dr "$IP"
