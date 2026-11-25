#!/bin/bash
# Ban/unban queue shared by fail2ban actions and the f2b-ban-worker service.
# fail2ban waits for each action to finish, so the actions only append a line here
# and return; scripts/f2b-ban-worker.sh does the real work in the background.
#
# Line format: "<ban|unban> <jail|-> <ip>"

F2B_SPOOL="${F2B_SPOOL:-/var/spool/fail2ban-whm}"
F2B_QUEUE="$F2B_SPOOL/queue"

f2b_queue_push() {
    local op="$1" jail="$2" ip="$3"
    [[ "$op" =~ ^(ban|unban)$ ]] || return 1
    [[ "$jail" =~ ^[A-Za-z0-9_.-]+$ ]] || jail="-"
    [[ "$ip" =~ ^[0-9a-fA-F:.]+$ ]] || return 1
    mkdir -p "$F2B_SPOOL" || return 1
    # flock keeps concurrent fail2ban threads from interleaving lines
    { flock -x 9; printf '%s %s %s\n' "$op" "$jail" "$ip" >> "$F2B_QUEUE"; } 9>"$F2B_QUEUE.lock"
}
