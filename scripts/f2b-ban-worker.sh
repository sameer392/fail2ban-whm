#!/bin/bash
# Background worker for the Fail2Ban ban queue (runs as the f2b-ban-worker systemd service).
# Reads lines written by csf-ban.sh / csf-unban.sh and applies them one by one.
# A ban runs csf-ban-process.sh (country/org check, ipset block, CSF record, email).
# An unban removes the ipset entry and the CSF deny entry.
#
# F2B_WORKER_ONCE=1 processes the queue once and exits (used for testing).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/f2b-queue.sh"
. "${SCRIPT_DIR}/f2b-ipset.sh"
. "${SCRIPT_DIR}/f2b-lookup.sh"
INTERVAL="${F2B_WORKER_INTERVAL:-1}"
WORK="$F2B_QUEUE.work"
LAST_PRUNE=0

process_file() {
    local op jail ip _
    while read -r op jail ip _; do
        case "$op" in
            ban)   "${SCRIPT_DIR}/csf-ban-process.sh" "$ip" "$jail" ;;
            unban) f2b_ipset_del "$ip"; f2b_timeout 60 /usr/sbin/csf -dr "$ip" ;;
        esac
    done < "$1"
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
