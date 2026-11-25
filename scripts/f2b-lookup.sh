#!/bin/bash
# Country and organisation lookups for ban decisions (sourced by csf-ban-process.sh).
#
# Local IP2Location databases only: no network calls, and no WHOIS. Each lookup is
# bounded by a timeout, and the result is cached per IP for F2B_CACHE_TTL seconds,
# so one IP hitting several jails or retrying is looked up once.
#
# Sets F2B_COUNTRY (ISO code or empty) and F2B_ORG (empty if unknown).

F2B_GEOIP_DIR="${F2B_GEOIP_DIR:-/etc/fail2ban/GeoIP}"
F2B_CACHE_DIR="${F2B_CACHE_DIR:-/var/cache/fail2ban-whm}"
F2B_CACHE_TTL="${F2B_CACHE_TTL:-86400}"

# Run a command with a time limit; if `timeout` is missing, run it unbounded.
f2b_timeout() {
    local t="$1"; shift
    if command -v timeout &>/dev/null; then timeout "$t" "$@"; else "$@"; fi
}

# f2b_mmdb_field <db> <ip> <path...>: print the first string value for the path
f2b_mmdb_field() {
    local db="$1" ip="$2"; shift 2
    { [ -f "$db" ] && command -v mmdblookup &>/dev/null; } || return 0
    f2b_timeout 5 mmdblookup -f "$db" -i "$ip" "$@" 2>/dev/null \
        | grep -m1 'utf8_string' | sed 's/.*"\([^"]*\)".*/\1/'
}

f2b_lookup_ip() {
    local ip="$1" f="$F2B_CACHE_DIR/$1" now mtime db asn path
    F2B_COUNTRY=""
    F2B_ORG=""
    now=$(date +%s)
    if [ -f "$f" ]; then
        mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        if [ $(( now - mtime )) -lt "$F2B_CACHE_TTL" ]; then
            F2B_COUNTRY=$(sed -n 1p "$f")
            F2B_ORG=$(sed -n 2p "$f")
            return 0
        fi
    fi

    db="$F2B_GEOIP_DIR/IP2LOCATION-LITE-DB1.mmdb"
    asn="$F2B_GEOIP_DIR/IP2LOCATION-LITE-ASN.mmdb"
    F2B_COUNTRY=$(f2b_mmdb_field "$db" "$ip" country iso_code | awk '/^[A-Z]{2}$/ {print; exit}')
    for path in as autonomous_system_organization organization; do
        F2B_ORG=$(f2b_mmdb_field "$asn" "$ip" "$path")
        [ -n "$F2B_ORG" ] && [ "$F2B_ORG" != "-" ] && break
        F2B_ORG=""
    done

    # Cache only when the databases exist, so a missing DB is not cached for a day
    if [ -f "$db" ]; then
        mkdir -p "$F2B_CACHE_DIR" 2>/dev/null && printf '%s\n%s\n' "$F2B_COUNTRY" "$F2B_ORG" > "$f" 2>/dev/null
    fi
    return 0
}
