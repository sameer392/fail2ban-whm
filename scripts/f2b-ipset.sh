#!/bin/bash
# Fast-path block set for Fail2Ban bans (sourced by csf-ban.sh / csf-unban.sh).
#
# `csf -d` / `csf -dr` rebuild CSF's firewall on every call (about 2-3 s each), so a
# burst of bans queues up behind them. Each ban is also added to the ipset "f2b-bans"
# and one iptables rule drops traffic from that set immediately.
# CSF's deny list is still updated, so WHM and csf -g keep showing the bans.
#
# Usage when executed:  f2b-ipset.sh restore   (re-load bans from csf.deny after boot)

F2B_IPSET_NAME="${F2B_IPSET_NAME:-f2b-bans}"
F2B_CSF_DENY="${F2B_CSF_DENY:-/etc/csf/csf.deny}"

f2b_ipset_ready() {
    command -v ipset &>/dev/null && command -v iptables &>/dev/null
}

# Create the set and its DROP rule if missing. Idempotent. Returns 1 if ipset is unavailable.
f2b_ipset_ensure() {
    f2b_ipset_ready || return 1
    ipset create "$F2B_IPSET_NAME" hash:ip family inet maxelem 262144 -exist 2>/dev/null || return 1
    iptables -C INPUT -m set --match-set "$F2B_IPSET_NAME" src -j DROP 2>/dev/null \
        || iptables -I INPUT 1 -m set --match-set "$F2B_IPSET_NAME" src -j DROP 2>/dev/null
    return 0
}

f2b_ipset_add() {
    f2b_ipset_ensure && ipset add "$F2B_IPSET_NAME" "$1" -exist 2>/dev/null
    return 0
}

f2b_ipset_del() {
    f2b_ipset_ready && ipset del "$F2B_IPSET_NAME" "$1" -exist 2>/dev/null
    return 0
}

# Re-add IPv4 bans recorded by Fail2Ban in csf.deny (ipset is memory-only and empty after reboot).
f2b_ipset_restore() {
    f2b_ipset_ensure || return 0
    [ -f "$F2B_CSF_DENY" ] || return 0
    grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}([ /]|$)' "$F2B_CSF_DENY" | grep -i 'Fail2Ban' \
        | awk '{print $1}' | while read -r ip; do
            ipset add "$F2B_IPSET_NAME" "$ip" -exist 2>/dev/null
        done
    return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "$1" in
        restore) f2b_ipset_restore ;;
        *) echo "usage: $0 restore" >&2; exit 1 ;;
    esac
fi
