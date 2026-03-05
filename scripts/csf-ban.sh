#!/bin/bash
# Fail2Ban CSF ban helper - adds IP to csf.deny with jail name and affected domain(s)
# Usage: csf-ban.sh <ip> <jail_name>
# Comment format: Fail2Ban <jail> <domain1, domain2, ...>

IP="$1"
JAIL="$2"
DOMLOGS="${DOMLOGS:-/usr/local/apache/domlogs}"

[ -z "$IP" ] || [ -z "$JAIL" ] && exit 1

# Find domains that had traffic from this IP (files containing this IP in recent logs)
DOMAINS=""
if [ -d "$DOMLOGS" ]; then
    DOMAINS=$(grep -lE "^${IP} " "$DOMLOGS"/*/* 2>/dev/null | while read -r f; do
        basename "$f" | sed 's/-ssl_log$//'
    done | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')
fi

# Build comment: Fail2Ban <jail> [domain1, domain2]
if [ -n "$DOMAINS" ]; then
    COMMENT="Fail2Ban ${JAIL} - ${DOMAINS}"
else
    COMMENT="Fail2Ban ${JAIL}"
fi

# Add to CSF (limit comment length for csf.deny)
COMMENT=$(echo "$COMMENT" | head -c 200)
/usr/sbin/csf -d "$IP" "$COMMENT"
