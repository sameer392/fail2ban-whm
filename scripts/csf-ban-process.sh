#!/bin/bash
# Fail2Ban CSF ban helper - adds IP to csf.deny with jail name and affected domain(s)
# Country whitelist (whitelist-countries.conf) applies ONLY to apache-high-volume.
# All other jails (wordpress-wp-login, apache-ua-*, etc.) always ban regardless of country.
# Exceptions for apache-high-volume: blacklisted orgs, multi-domain abuse override whitelist.
# Usage: csf-ban-process.sh <ip> <jail_name>   (run by f2b-ban-worker.sh, not by fail2ban directly)
# Comment format: Fail2Ban <jail> - <domain1, domain2, ...>

IP="$1"
JAIL="$2"
SCRIPT_DIR="$(dirname "$0")"
CONFIG="/etc/fail2ban/conf.d/whitelist-countries.conf"
BLOCKLIST_CONFIG="/etc/fail2ban/conf.d/blocklist-organizations.conf"
DOMLOGS="${DOMLOGS:-/usr/local/apache/domlogs}"

[ -z "$IP" ] || [ -z "$JAIL" ] && exit 1
[ -f "${SCRIPT_DIR}/f2b-ipset.sh" ] && . "${SCRIPT_DIR}/f2b-ipset.sh"

# Skip private/local IPv4
[[ "$IP" =~ ^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]] && exit 0
# Skip loopback, link-local, ULA, IPv4-mapped IPv6
[[ "$IP" == "::1" ]] && exit 0
[[ "$IP" == fe80:* || "$IP" == FE80:* ]] && exit 0
[[ "$IP" == fc* || "$IP" == fd* || "$IP" == FC* || "$IP" == FD* ]] && exit 0
[[ "$IP" == ::ffff:* || "$IP" == ::FFFF:* ]] && exit 0

# Optional IPv6: skip unless ENABLE_IPV6=1 (IPv4-only servers stay IPv4)
if [[ "$IP" == *:* ]]; then
    ENABLE_IPV6=0
    [ -f /etc/fail2ban/conf.d/ipv6.conf ] && . /etc/fail2ban/conf.d/ipv6.conf
    [ "${ENABLE_IPV6:-0}" != "1" ] && exit 0
fi


# CMS / editor path allow list (WHM → Whitelists). Sourced for country-scoped patterns.
[ -f "${SCRIPT_DIR}/cms-allow.sh" ] && . "${SCRIPT_DIR}/cms-allow.sh"
# Lookups (cached, local-only) and f2b_timeout
. "${SCRIPT_DIR}/f2b-lookup.sh"

# Country whitelist applies ONLY to apache-high-volume; all other jails always ban
[[ "$JAIL" == apache-high-volume ]] && SKIP_WHITELIST=0 || SKIP_WHITELIST=1

# Find domains that had traffic from this IP (needed for comment and multi-domain check)
DOMAINS=""
DOMAIN_COUNT=0
SCANNER_DOMAIN_COUNT=0
if [ -n "$F2B_DOMAINS_MAP" ] && [ -f "$F2B_DOMAINS_MAP" ]; then
    # Batch map written by f2b-ban-worker.sh (one domlog scan for the whole batch)
    DOMAINS=$(awk -F'\t' -v ip="$IP" '$1 == ip {print $2}' "$F2B_DOMAINS_MAP" | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')
elif [ -d "$DOMLOGS" ]; then
    IP_ESC=$(printf '%s' "$IP" | sed 's/[.[\*^$]/\\&/g')
    DOMAINS=$(grep -lE "^${IP_ESC} " "$DOMLOGS"/*/* 2>/dev/null | grep -vE 'bytes_log$|ftp_log$|placeholder' | while read -r f; do
        basename "$f" | sed 's/-ssl_log$//'
    done | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')
fi
[ -n "$DOMAINS" ] && DOMAIN_COUNT=$(echo "$DOMAINS" | tr ',' '\n' | wc -l)
SCANNER_DOMAIN_COUNT=$DOMAIN_COUNT

# Load ignored countries
WHITELIST_COUNTRIES=""
[ -f "$CONFIG" ] && . "$CONFIG"

# Load blocklist and multi-domain threshold
BLOCKED_ORGANIZATIONS=""
MULTI_DOMAIN_ABUSE_THRESHOLD=0
[ -f "$BLOCKLIST_CONFIG" ] && . "$BLOCKLIST_CONFIG"

# Check country and skip if whitelisted (with exceptions) - skip for apache-ua-* jails
SKIP_BAN=0
if [ "$SKIP_WHITELIST" != "1" ] && [ -n "$WHITELIST_COUNTRIES" ]; then
    # Local IP2Location databases only, bounded and cached (see f2b-lookup.sh)
    f2b_lookup_ip "$IP"
    COUNTRY="$F2B_COUNTRY"
    if [ -n "$COUNTRY" ]; then
        IS_WHITELISTED=0
        for c in $(echo "$WHITELIST_COUNTRIES" | tr ',' ' '); do
            c=$(echo "$c" | tr -d ' ')
            [ "$COUNTRY" = "$c" ] && { IS_WHITELISTED=1; break; }
        done
        if [ "$IS_WHITELISTED" = "1" ]; then
            SKIP_BAN=1
            # Exception 1: Multi-domain abuse - scanning many domains (CMS paths from
            # cms-allow.conf for this country are not counted).
            if [ "$JAIL" = "apache-high-volume" ] && type cms_allow_pattern_regex &>/dev/null; then
                EDITOR_RE=$(cms_allow_pattern_regex "$COUNTRY")
                SCANNER_DOMAINS=$(cms_allow_scanner_domains "$IP" "$EDITOR_RE")
                SCANNER_DOMAIN_COUNT=0
                [ -n "$SCANNER_DOMAINS" ] && SCANNER_DOMAIN_COUNT=$(printf '%s\n' "$SCANNER_DOMAINS" | grep -c .)
            fi
            if [ -n "$MULTI_DOMAIN_ABUSE_THRESHOLD" ] && [ "$MULTI_DOMAIN_ABUSE_THRESHOLD" -gt 0 ] 2>/dev/null; then
                if [ "$SCANNER_DOMAIN_COUNT" -ge "$MULTI_DOMAIN_ABUSE_THRESHOLD" ] 2>/dev/null; then
                    SKIP_BAN=0
                fi
            fi
            # Exception 2: Blacklisted organization - ban Microsoft, DigitalOcean, etc.
            if [ "$SKIP_BAN" = "1" ] && [ -n "$BLOCKED_ORGANIZATIONS" ]; then
                # ORG comes from f2b_lookup_ip (local ASN database, cached). No WHOIS:
                # it has no timeout and can hang the queue.
                ORG="$F2B_ORG"
                for bl in $(echo "$BLOCKED_ORGANIZATIONS" | tr ',' ' '); do
                    bl=$(echo "$bl" | tr -d ' ')
                    [ -z "$bl" ] && continue
                    if echo "$ORG" | grep -qiF "$bl"; then
                        SKIP_BAN=0
                        break
                    fi
                done
            fi
            [ "$SKIP_BAN" = "1" ] && exit 0
        fi
    else
        # Country unknown (not in the local IP2Location database). It cannot be shown to be
        # whitelisted, so the default is to ban. Set UNKNOWN_COUNTRY_ACTION=skip in
        # conf.d/whitelist-countries.conf to exempt these IPs instead.
        [ "${UNKNOWN_COUNTRY_ACTION:-ban}" = "skip" ] && exit 0
    fi
fi

# Build comment
if [ -n "$DOMAINS" ]; then
    COMMENT="Fail2Ban ${JAIL} - ${DOMAINS}"
else
    COMMENT="Fail2Ban ${JAIL}"
fi

COMMENT=$(echo "$COMMENT" | head -c 200)
# Block at once via ipset; CSF call below is only for its deny list / WHM view
f2b_ipset_add "$IP"
f2b_timeout 60 /usr/sbin/csf -d "$IP" "$COMMENT"

# Optional: send email alert on ban (SMTP)
EMAIL_CONF="${SCRIPT_DIR}/email-alerts.conf"
if [ -f "$EMAIL_CONF" ] && [ -r "$EMAIL_CONF" ]; then
    . "$EMAIL_CONF"
    if [ "${ENABLED:-0}" = "1" ] && [ -n "$EMAIL_TO" ] && [ -n "$SMTP_HOST" ] && command -v curl &>/dev/null; then
        SUBJ="[Fail2Ban] $IP banned ($JAIL)"
        BODY="IP $IP was banned by Fail2Ban (jail: $JAIL). Domains: ${DOMAINS:--}. $(date)"
        FROM="${EMAIL_FROM:-fail2ban@localhost}"
        MSG="From: $FROM
To: $EMAIL_TO
Subject: $SUBJ

$BODY"
        case "${SMTP_SECURE:-tls}" in
            ssl) PORT="${SMTP_PORT:-465}" ; URL="smtps://${SMTP_HOST}:${PORT}" ; EXTRA="" ;;
            tls) PORT="${SMTP_PORT:-587}" ; URL="smtp://${SMTP_HOST}:${PORT}" ; EXTRA="--ssl-reqd" ;;
            *)   PORT="${SMTP_PORT:-25}"  ; URL="smtp://${SMTP_HOST}:${PORT}" ; EXTRA="" ;;
        esac
        if [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ]; then
            echo "$MSG" | curl -s --connect-timeout 10 --max-time 30 --url "$URL" --mail-from "$FROM" --mail-rcpt "$EMAIL_TO" --user "$SMTP_USER:$SMTP_PASS" $EXTRA -T - 2>/dev/null
        else
            echo "$MSG" | curl -s --connect-timeout 10 --max-time 30 --url "$URL" --mail-from "$FROM" --mail-rcpt "$EMAIL_TO" $EXTRA -T - 2>/dev/null
        fi
    fi
fi
