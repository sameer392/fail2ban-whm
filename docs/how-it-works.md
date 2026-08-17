# How It Works

## Blocking Flow

```
Attacker → Internet → Server
                         → iptables (fail2ban) / CSF → DROP (blocked)
                         → LiteSpeed (never reached if banned)
                         → WordPress
```

## End-to-End Flow

1. **Monitor** – Fail2ban watches `/usr/local/apache/domlogs/*/*` (all cPanel domain logs)
2. **Filter** – Matches wp-login.php POSTs or high-volume page requests (excludes crawlers, WordPress admin, and static assets)
3. **Trigger** – 5+ wp-login in 5 min OR 100+ counted requests in 10 min
4. **Ban** – `scripts/csf-ban.sh` adds IP to CSF; skips whitelisted countries
5. **Unban** – After bantime (1 hr), fail2ban runs `csf -dr <ip>` to remove from CSF
