#!/bin/bash
# CMS / editor allow helper for apache-high-volume
# Used as fail2ban ignorecommand and sourced by csf-ban.sh
#
# ignorecommand: exit 0 = do not ban (legitimate editor from allowed country)
#                exit 1 = do not ignore (ban may proceed)
#
# Usage:
#   cms-allow.sh <ip>                 # ignorecommand
#   cms-allow.sh country <ip>         # print ISO country code
#   cms-allow.sh patterns <cc>        # print grep -E regex of enabled patterns for country

CMS_ALLOW_CONF="${CMS_ALLOW_CONF:-/etc/fail2ban/conf.d/cms-allow.conf}"
CMS_ALLOW_DOMLOGS="${DOMLOGS:-/usr/local/apache/domlogs}"
CMS_ALLOW_WINDOW_SECS="${CMS_ALLOW_WINDOW_SECS:-900}"
CMS_ALLOW_MIN_RATIO="${CMS_ALLOW_MIN_RATIO:-80}"

cms_allow_country() {
    local ip="$1"
    local country="" db
    [ -z "$ip" ] && return 1
    db="/etc/fail2ban/GeoIP/IP2LOCATION-LITE-DB1.mmdb"
    if [ -f "$db" ] && command -v mmdblookup &>/dev/null; then
        country=$(mmdblookup -f "$db" -i "$ip" country iso_code 2>/dev/null | awk -F'"' '$2 ~ /^[A-Z]{2}$/ {print $2; exit}')
    fi
    if [ -z "$country" ] && command -v curl &>/dev/null; then
        local enc
        enc=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$ip" 2>/dev/null || printf '%s' "$ip")
        country=$(curl -s --connect-timeout 2 --max-time 4 "http://ip-api.com/json/${enc}?fields=countryCode" 2>/dev/null | grep -o '"countryCode":"[A-Z]*"' | cut -d'"' -f4)
    fi
    printf '%s' "$country"
}

# Enabled patterns whose country list includes $1 (or has empty countries = all).
# Prints a single grep -E regex, or empty if none.
cms_allow_pattern_regex() {
    local cc="$1"
    local name pattern countries enabled re=""
    [ ! -f "$CMS_ALLOW_CONF" ] && return 0
    while IFS=$'\t' read -r name pattern countries enabled || [ -n "$name" ]; do
        [[ "$name" =~ ^[[:space:]]*# ]] && continue
        [ -z "$pattern" ] && continue
        [ "${enabled:-1}" != "1" ] && continue
        countries=$(echo "$countries" | tr 'a-z' 'A-Z' | tr -d ' ')
        if [ -n "$countries" ]; then
            echo ",${countries}," | grep -q ",${cc}," || continue
        fi
        [ -n "$re" ] && re+="|"
        re+="$pattern"
    done < "$CMS_ALLOW_CONF"
    printf '%s' "$re"
}

# Recent log files only (ignorecommand runs per match; keep this cheap).
cms_allow_recent_logs() {
    local mins=$(( (CMS_ALLOW_WINDOW_SECS + 59) / 60 ))
    [ "$mins" -lt 1 ] && mins=1
    find "$CMS_ALLOW_DOMLOGS" -maxdepth 2 -type f -mmin "-${mins}" \
        ! -name '*bytes_log' ! -name '*ftp_log*' ! -name '*placeholder*' 2>/dev/null
}

# Print unique domain names (ssl suffix stripped) with recent *non-editor* hits.
# $1=ip  $2=editor_regex (empty = all recent hits count as scanner)
cms_allow_scanner_domains() {
    local ip="$1"
    local editor_re="$2"
    local ip_esc cutoff
    ip_esc=$(printf '%s' "$ip" | sed 's/[.[\*^$]/\\&/g')
    cutoff=$(date -d "${CMS_ALLOW_WINDOW_SECS} seconds ago" +%s 2>/dev/null || date -d '15 minutes ago' +%s)
    cms_allow_recent_logs | while read -r f; do
        grep -qE "^${ip_esc} " "$f" 2>/dev/null || continue
        local hits
        hits=$(grep -E "^${ip_esc} " "$f" 2>/dev/null || true)
        [ -z "$hits" ] && continue
        if [ -n "$editor_re" ]; then
            hits=$(printf '%s\n' "$hits" | grep -vE "$editor_re" || true)
        fi
        [ -z "$hits" ] && continue
        printf '%s\n' "$hits" | awk -v cutoff="$cutoff" '
            BEGIN {
                split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", mn, " ")
                for (i = 1; i <= 12; i++) mon[mn[i]] = sprintf("%02d", i)
            }
            match($0, /\[([0-9]{2})\/([A-Za-z]{3})\/([0-9]{4}):([0-9]{2}):([0-9]{2}):([0-9]{2})/, a) {
                ts = mktime(a[3] " " mon[a[2]] " " a[1] " " a[4] " " a[5] " " a[6])
                if (ts >= cutoff) { found = 1; exit }
            }
            END { exit !found }
        ' && basename "$f" | sed 's/-ssl_log$//'
    done | sort -u
}

# Exit 0 if this IP should not be banned (editor from allowed country).
cms_allow_should_ignore() {
    local ip="$1"
    local cc editor_re ip_esc total matched
    [ -z "$ip" ] && return 1
    [ ! -f "$CMS_ALLOW_CONF" ] && return 1
    cc=$(cms_allow_country "$ip")
    [ -z "$cc" ] && return 1
    editor_re=$(cms_allow_pattern_regex "$cc")
    [ -z "$editor_re" ] && return 1

    ip_esc=$(printf '%s' "$ip" | sed 's/[.[\*^$]/\\&/g')
    # Recent files only (mtime window). Sample last 200 hits; no per-line date parse.
    local sample
    sample=$(cms_allow_recent_logs | xargs grep -hE "^${ip_esc} " 2>/dev/null | tail -n 200)
    [ -z "$sample" ] && return 1
    total=$(printf '%s\n' "$sample" | wc -l)
    total=${total// /}
    [ "${total:-0}" -lt 1 ] && return 1
    matched=$(printf '%s\n' "$sample" | grep -cE "$editor_re" || true)
    matched=${matched// /}
    [ $((matched * 100 / total)) -ge "$CMS_ALLOW_MIN_RATIO" ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        country) cms_allow_country "$2"; echo; exit 0 ;;
        patterns) cms_allow_pattern_regex "$2"; echo; exit 0 ;;
        "") exit 1 ;;
        *) cms_allow_should_ignore "$1" ;;
    esac
fi
