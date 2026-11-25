#!/bin/bash
# Background worker for the Fail2Ban ban queue (runs as the f2b-ban-worker systemd service).
# Reads lines written by csf-ban.sh / csf-unban.sh and applies them one by one.
# A ban runs csf-ban-process.sh (country/org check, ipset block, CSF record, email).
# An unban removes the ipset entry and the CSF deny entry.
#
# Domain lookup is batched: each batch scans the domlogs once for all of its banned IPs
# and passes the result to csf-ban-process.sh through F2B_DOMAINS_MAP.
#
# F2B_WORKER_ONCE=1 processes the queue once and exits (used for testing).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/f2b-queue.sh"
. "${SCRIPT_DIR}/f2b-ipset.sh"
. "${SCRIPT_DIR}/f2b-lookup.sh"
INTERVAL="${F2B_WORKER_INTERVAL:-1}"
DOMLOGS="${DOMLOGS:-/usr/local/apache/domlogs}"
WORK="$F2B_QUEUE.work"
LAST_PRUNE=0

# build_domain_map <ipfile> <outfile>: one pass over the domlogs for all IPs in the batch.
# Output lines: "<client ip><TAB><domain>". Only the first field (client IP) counts.
build_domain_map() {
    [ -d "$DOMLOGS" ] || { : > "$2"; return 0; }
    grep -HF -f "$1" "$DOMLOGS"/*/* 2>/dev/null \
        | grep -vE 'bytes_log:|ftp_log:|placeholder' \
        | awk -F: '{
            path = $1
            rest = substr($0, length(path) + 2)
            split(rest, f, " ")
            n = split(path, p, "/")
            d = p[n]; sub(/-ssl_log$/, "", d)
            print f[1] "\t" d
        }' | sort -u > "$2"
}

process_file() {
    local file="$1" op jail ip _ ipfile map
    ipfile="$file.ips"; map="$file.map"
    # Collect banned IPs and build the domain map once
    awk '$1 == "ban" && $3 != "" {print $3}' "$file" | sort -u > "$ipfile"
    if [ -s "$ipfile" ]; then
        build_domain_map "$ipfile" "$map"
        export F2B_DOMAINS_MAP="$map"
    else
        unset F2B_DOMAINS_MAP
    fi
    while read -r op jail ip _; do
        case "$op" in
            ban)   "${SCRIPT_DIR}/csf-ban-process.sh" "$ip" "$jail" ;;
            unban) f2b_ipset_del "$ip"; f2b_timeout 60 /usr/sbin/csf -dr "$ip" ;;
        esac
    done < "$file"
    rm -f "$ipfile" "$map"
    unset F2B_DOMAINS_MAP
}

# Drop lookup-cache entries older than the TTL (about once an hour)
prune_cache() {
    local now
    now=$(date +%s)
    [ $(( now - LAST_PRUNE )) -lt 3600 ] && return 0
    LAST_PRUNE=$now
    [ -d "$F2B_CACHE_DIR" ] && find "$F2B_CACHE_DIR" -type f -mmin +$(( F2B_CACHE_TTL / 60 )) -delete 2>/dev/null
    return 0
}

mkdir -p "$F2B_SPOOL"
f2b_ipset_ensure

while true; do
    # Leftover batch from a crash is processed first
    if [ -s "$WORK" ]; then
        process_file "$WORK"
        rm -f "$WORK"
    fi
    if [ -s "$F2B_QUEUE" ]; then
        { flock -x 9; mv -f "$F2B_QUEUE" "$WORK"; } 9>"$F2B_QUEUE.lock"
        [ -s "$WORK" ] && { process_file "$WORK"; rm -f "$WORK"; }
    fi
    [ -n "$F2B_WORKER_ONCE" ] && exit 0
    prune_cache
    sleep "$INTERVAL"
done
