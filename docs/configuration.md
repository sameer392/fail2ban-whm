# Configuration

## Jails and Settings

### Jail Settings (editable via WHM UI)

| Jail | maxretry | findtime | bantime | Purpose |
|------|----------|----------|---------|---------|
| wordpress-wp-login | 5 | 300 sec (5 min) | 3600 sec (1 hr) | wp-login brute force |
| apache-high-volume | 100 | 600 sec (10 min) | 3600 sec (1 hr) | High-volume abuse |

### Files Deployed

| File | Purpose |
|------|---------|
| filter.d/wordpress-wp-login.conf | Match POST to wp-login.php (login attempts only; GET ignored) |
| filter.d/apache-high-volume.conf | Match requests; ignoreregex excludes crawlers + whitelist IPs. CMS paths are country-scoped via cms-allow.conf |
| jail.d/*.conf | Jail definitions (backend=polling, logpath, banaction). apache-high-volume uses ignorecommand → cms-allow.sh |
| action.d/csf-domain.conf | Custom action: actionban → csf-ban.sh, actionunban → csf -dr |
| scripts/csf-ban.sh | Adds IP to csf.deny; skips whitelisted countries; multi-domain check uses cms-allow.conf paths for that country |
| scripts/cms-allow.sh | ignorecommand + path/country helper (WHM-managed cms-allow.conf) |
| conf.d/cms-allow.conf | CMS/editor path rules: name, pattern, countries, enabled (edit in WHM) |
| conf.d/whitelist-countries.conf | `WHITELIST_COUNTRIES=IN,US` (ISO codes) |
| conf.d/whitelist-domains.conf | Domains/users excluded from protection (see Whitelists tab) |
| /etc/csf/csf.conf (CC_DENY) | Countries to block at firewall - edited via Blacklist tab |
| fail2ban.d/loglevel-verbose.conf | Loglevel override (INFO or WARNING) |
| logrotate.d/fail2ban | → /etc/logrotate.d/fail2ban |

---

## Whitelisting

### IP Whitelist (whitelist-ips.conf)

IPs/CIDRs in this file are whitelisted (excluded from bans). Supported: single IP, /24, /28, /29, /32.

1. Edit `conf.d/whitelist-ips.conf`
2. Run `update-whitelist.sh` – regenerates filter ignoreregex
3. Run `update.sh` – deploy and restart

### Country Whitelist (whitelist-countries.conf)

**Applies only to `apache-high-volume` jail.** IPs from whitelisted countries are not banned by apache-high-volume (high-traffic abuse), unless they scan many domains with traffic that is not in the CMS/editor allow list for that country (WHM → Whitelists → CMS / Editor paths). **All other jails (wordpress-wp-login, apache-ua-*, etc.) always ban regardless of country**—wp-login brute force and User-Agent abuse are blocked even from whitelisted countries.

### CMS / Editor paths (conf.d/cms-allow.conf)

WordPress admin, REST, assets, and static files are **not** ignored for every IP. Each rule has a path pattern and one or more country codes. Only matching requests from those countries are treated as legitimate editor traffic.

Edit via WHM → Fail2Ban Manager → Whitelists → CMS / Editor paths (add / edit / delete). Changes apply immediately (no fail2ban restart). Default rules allow typical WordPress editor paths from `IN`.

```ini
# conf.d/whitelist-countries.conf
WHITELIST_COUNTRIES=IN,US,GB
```

- **IN** = India, **US** = United States, **GB** = United Kingdom
- Country lookup: IP2Location LITE DB1 → ip-api.com fallback
- Setup: Run `scripts/setup-ip2location.sh` during install or manually

### Blacklist Countries (CSF CC_DENY)

IPs from blacklisted countries are **blocked at the firewall** (CSF CC_DENY). All traffic from these countries is denied before reaching the server. Requires CSF and `/etc/csf/csf.conf`.

The plugin reads from and writes directly to `/etc/csf/csf.conf`. Edit via WHM → Blacklist → Blacklist Countries. Click **Save** to update CC_DENY and restart CSF (`csf -r`).

---

### Excluded Domains / Users (conf.d/whitelist-domains.conf)

Domains and cPanel users listed here are **excluded from fail2ban protection**—their logs are not monitored by apache-high-volume or wordpress-wp-login.

```ini
EXCLUDED_USERS=user1,user2
EXCLUDED_DOMAINS=example.com,cdn.example.com
```

- **EXCLUDED_USERS** – cPanel usernames; all their domains are excluded
- **EXCLUDED_DOMAINS** – Domain names; matches log filename (e.g. `example.com`, `example.com-ssl_log`)

Edit via WHM → Whitelists → Excluded Domains/Users. After saving, run `update.sh` or use "Save & Deploy" in the UI.

---

### Organization Lookup (for WHM display and blacklisted-orgs)

Organization (Microsoft, DigitalOcean, etc.) is shown in the Banned IPs table. Lookup order:
1. SQLite cache (local)
2. IP2Location LITE ASN mmdb (local file)
3. whois (system tool)
4. ip-api.com (fallback)

For local mmdb, run `scripts/setup-ip2location-asn.sh` (requires IP2LOCATION_TOKEN in `/etc/fail2ban/GeoIP/ip2location.conf`). Without it, whois/ip-api.com are used. All results are cached in SQLite.

---

## CSF Integration

- **Comment format:** `Fail2Ban <jail> - <domain1, domain2, ...>`
- **Example:** `Fail2Ban wordpress-wp-login - example.com` or `Fail2Ban apache-high-volume - site1.com, site2.com`
- Domains are resolved from domlogs when the ban is triggered
- Auto-unban: When bantime expires, fail2ban runs `csf -dr <ip>`
