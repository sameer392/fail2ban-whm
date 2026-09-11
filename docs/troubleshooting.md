# Troubleshooting

## Domlog path differs

Edit jail config: `logpath = /path/to/your/logs/*` then run `update.sh` or `systemctl restart fail2ban`.

## No `fail2ban` binary

Use `fail2ban-client` for management. There is no standalone `fail2ban` command.

## Ban action (firewalld vs iptables)

- EL9 installs fail2ban-firewalld; fail2ban auto-selects backend
- On cPanel with CSF, firewalld is usually disabled; fail2ban uses iptables
- CSF bans are separate from iptables; csf-ban.sh adds to csf.deny

## IP not being banned

- **Country whitelist:** Check conf.d/whitelist-countries.conf; IPs from listed countries are skipped
- **IP whitelist:** Check whitelist-ips.conf and run update-whitelist.sh + update.sh
- **Time window:** findtime is a sliding window; requests must exceed maxretry within that window
- **Test filter:** `fail2ban-regex /path/to/log /etc/fail2ban/filter.d/wordpress-wp-login.conf`

## High-volume jail caution

CMS/editor paths (wp-admin, REST, static files, etc.) are configured in WHM → Whitelists → CMS / Editor paths and apply only to the country codes on each rule. Other countries are still counted and can be banned. API clients or CDNs that request many non-static URLs may still be affected. To disable the jail: set `enabled = false` in `jail.d/apache-high-volume.conf` and run update.sh.

## Site unreachable from iPhone / iPad / Mac (Darwin User-Agent)

Before 1.0.8, `apache-ua-keywords` treated `Darwin` as a bot keyword. Apple browsers send Darwin in the User-Agent (for example Opera Mini / CFNetwork on iOS), so **one request** (`maxretry=1`) banned the visitor for `bantime` (default 4 hours). The site stayed up for other clients.

Upgrade to 1.0.8 (Darwin is ignored), then unban the client IP:

```bash
fail2ban-client set apache-ua-keywords unbanip <ip>
csf -dr <ip>
```

Do not add `Darwin` back in WHM → Settings → User-Agent Keyword Blocking.

## WordPress site owner banned (timeout to wp-admin)

Check WHM → Whitelists → CMS / Editor paths: the path (e.g. `wp-admin`) must be enabled and the client's country code listed. Unban with `csf -dr <ip>` and `fail2ban-client set apache-high-volume unbanip <ip>`.
