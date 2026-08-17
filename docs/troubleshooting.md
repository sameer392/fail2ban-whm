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

The apache-high-volume jail ignores WordPress admin, REST API, plugin/theme assets, and static files, so CMS editors are not counted. Scrapers hitting HTML/PHP pages are still banned. API clients or CDNs that request many non-static URLs may still be affected. To disable: set `enabled = false` in `jail.d/apache-high-volume.conf` and run update.sh.

## WordPress site owner banned (timeout to wp-admin)

If a client IP from a whitelisted country was banned while editing several sites, check that `apache-high-volume` filter ignoreregex includes `wp-admin` and that `csf-ban.sh` uses scanner-domain counting (recent non-CMS hits). Unban with `csf -dr <ip>` and `fail2ban-client set apache-high-volume unbanip <ip>`.
