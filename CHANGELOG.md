# Changelog

## [1.0.15] - 2026-11-26

### Fixed
- The Country column in the Banned IPs table showed `-` for every row. The lookup passed the database path as one argument, so the country was never found. Each key is now passed separately. Bans were not affected, because the ban decision uses its own lookup.

## [1.0.14] - 2026-11-26

### Fixed
- The Unban button in the Banned IPs table failed with "Security token missing or invalid". The table is loaded by AJAX as HTML, and the CSRF token was not added to its forms. The token is now added to that table, and JSON responses are unchanged.

## [1.0.13] - 2026-11-26

### Performance
- The Banned IPs table no longer runs `fail2ban-client status` and the banned-IP list for every jail before it loads. Those calls ran on every page request, including the table's own AJAX request, and made it take seconds.

## [1.0.12] - 2026-11-26

### Fixed
- Organisation names with spaces (e.g. `Microsoft Corporation`) were saved to `blocklist-organizations.conf` unquoted. The ban script loaded that file as shell code, so every ban printed errors and the name never matched. The plugin now saves the value quoted and reads it back without the quotes.

### Performance
- The WHM plugin's Banned IPs tab no longer waits on the network. Country and organisation come only from the local IP2Location databases. WHOIS and ip-api.com are no longer called while the page renders, and unknown IPs are retried on the next load instead of being cached as unknown.
- Affected domains come from the domain comment in `csf.deny`. The domlog scan that ran for each row is no longer part of the page.
- `csf.deny` is read once per page load, not once per row.

## [1.0.11] - 2026-11-26

### Fixed
- `f2b-lookup.sh` was not deployed by `install.sh` or `update.sh`, although `csf-ban-process.sh` and `f2b-ban-worker.sh` load it. Without it, bans were not recorded in CSF's deny list and the country/org lookup did not run. Upgrade to this version to fix it; check with `ls /etc/fail2ban/scripts/f2b-lookup.sh`.

## [1.0.10] - 2026-11-26
### Security
- `email-alerts.conf` (holds the SMTP password) is created owner-only, so it is never readable by others. Its path is now `/etc/fail2ban/conf.d/`, the same place the WHM plugin saves it. Before this, the ban script looked in a different folder, so alert emails were never sent from the saved settings. The ban script only loads the file if it is root-owned with mode 600. `install.sh` and `update.sh` enforce the same permissions on an existing file.
- WHM plugin: all ban-database queries now use PDO with bound parameters (`f2b_db_query()`), instead of the `sqlite3` command line with SQL built from strings. Queries that run per IP are checked against a valid-IP filter first.
- WHM plugin: the domlog grep for an IP is passed through `escapeshellarg`, and the IP is checked with `FILTER_VALIDATE_IP` before it reaches the shell.
- WHM plugin: every POST request now needs a CSRF token (`csrf_token` form field or `X-CSRF-Token` header). Requests without a valid token are rejected before any action runs. This covers unban, whitelist and blacklist changes, jail settings, update and reload actions. The token is derived from a root-only key in `/var/lib/fail2ban-whm/csrf.key`, which is created on first use.
- The two AJAX actions that change state (`clean_expired_bips` and `apply_blacklist_log`) were GET requests. They are now POST-only and send the token.

### Changed
- `jail.local` is created once by `install.sh` / `update.sh` (empty) and is never overwritten. Put per-server values such as `maxretry` there. Upgrades copy `jail.d/*.conf` from the repo, so values edited in those files are reset on every update. `update.sh` backs up `jail.local` with the other jail files.
- **Upgrade note:** servers that already tuned `apache-high-volume` or `wordpress-wp-login` in `jail.d/` must move those values into `jail.local` before the upgrade, or the upgrade resets them to the repo defaults.

## [1.0.9] - 2026-11-25

### Other
- New WHM plugin icon (firewall wall with a ban badge).

### Performance
- Domain lookup for ban comments is batched. The worker scans the domlogs once per batch for all banned IPs (previously once per ban), and `csf-ban-process.sh` reads the result from that batch.
- Lookups are bounded and cached. The new `f2b-lookup.sh` reads country and organisation from the local IP2Location databases with a 5-second timeout, and caches the result per IP for 24 hours in `/var/cache/fail2ban-whm`. The worker prunes expired entries hourly. `csf -d` and `csf -dr` run with a 60-second timeout so a hung CSF call cannot block the queue.
- The WHOIS fallback is removed. WHOIS has no timeout and could hang the ban queue.
- Country and organisation checks use only the local IP2Location databases. The ip-api.com fallback is removed from `csf-ban-process.sh` and `cms-allow.sh`. `cms-allow.sh` runs as fail2ban's `ignorecommand` on every matching log line, so it made one network call per line; its free-tier rate limit also made lookups fail under attack.
- **Behaviour change:** an IP that is not in the local database is now banned by default. Before, a failed lookup skipped the ban. To keep the old behaviour, set `UNKNOWN_COUNTRY_ACTION=skip` in `conf.d/whitelist-countries.conf`. Servers without the IP2Location database should set this to `skip` if they rely on the country whitelist.
- Ban processing moved out of fail2ban's action thread. `csf-ban.sh` and `csf-unban.sh` now only append a line to a queue (`/var/spool/fail2ban-whm/queue`) and return. The new `f2b-ban-worker` systemd service applies the queue in the background (`csf-ban-process.sh` does the country/org check, domain comment, ipset block, CSF record and email). Previously each ban blocked detection of the other IPs while its lookups and `csf -d` ran.
- Bans are applied to an `ipset` set (`f2b-bans`) with one iptables DROP rule, so a ban takes effect immediately instead of waiting on `csf -d` (which rebuilds the CSF firewall on every call). CSF's deny list is still updated for WHM and `csf -g`.
- Unbans go through the new `csf-unban.sh`, which removes the IP from the set as well as CSF.
- After a reboot, `f2b-ipset.sh restore` (run as the action's `actionstart`) reloads Fail2Ban bans from `csf.deny`.
- The installer installs `ipset` if it's missing.

### Added
- **Exim/Dovecot mail login brute-force jail** (`exim-dovecot-auth`): reads `/var/log/exim_mainlog` and bans source IPs with 5 failed Dovecot logins (SMTP AUTH, IMAP, POP3) within 10 minutes for 1 hour. Protects against credential-guessing campaigns on mail accounts, which CSF's built-in SMTP AUTH detection was not catching on cPanel servers using Dovecot.

### Upgrade notes
1. Update via WHM → Fail2Ban Manager → Update, or `/usr/share/fail2ban/scripts/update-from-github.sh`.
2. Confirm the jail is active: `fail2ban-client status exim-dovecot-auth`.
3. Trusted IPs that must never be banned go in `ignoreip` in `/etc/fail2ban/jail.d/exim-dovecot-auth.conf`. Note `update-whitelist.sh` does not apply to this jail, and an update overwrites the file, so re-check after updating.
4. fail2ban was previously stopped on some servers. `install.sh` / `update.sh` enable and restart it, which also starts the existing UA and wp-login jails.


## [1.0.8] - 2026-09-11

### Fixed
- Stop banning iOS/macOS visitors: `Darwin` is in every Apple User-Agent (CFNetwork). With `maxretry=1` that made sites look “down most of the time” after one iPhone request (ticket #162234).
- Default `useragent-keywords.conf` and `apache-ua-keywords` filter no longer include Darwin.
- `update-useragent-jails.sh` comments Darwin out of existing configs and skips it even if someone re-adds it.
- GitHub updates re-apply that strip after restoring `conf.d` (user edits are otherwise preserved).
- WHM User-Agent settings ignore Darwin on save.

### Upgrade notes
1. Update via WHM → Fail2Ban Manager → Update, or:
   ```bash
   /usr/share/fail2ban/scripts/update-from-github.sh v1.0.8
   ```
2. Confirm the combined UA filter has no Darwin regex:
   ```bash
   grep -i Darwin /etc/fail2ban/filter.d/apache-ua-keywords.conf /etc/fail2ban/conf.d/useragent-keywords.conf
   ```
   Expect only comments, not an active `Darwin|` line or failregex.
3. Existing Darwin bans expire with bantime (default 4 hours). Unban sooner in WHM → Banned IPs, or:
   ```bash
   fail2ban-client set apache-ua-keywords unbanip <ip>
   csf -dr <ip>
   ```

## [1.0.7] - 2026-09-02

### Performance (load fix)
- Switch domlog jails from `backend = polling` to **`pyinotify`** (event-driven). Polling every second across 1000+ logs × multiple jails was a major fail2ban CPU cost on busy cPanel servers.
- Set `usedns = no` on domlog jails to avoid reverse-DNS on every match.
- Add `jail.d/98-domlog-backend.conf` so pyinotify wins even if a generator still writes `polling`.
- Merge per-keyword User-Agent jails (`apache-ua-empty`, `apache-ua-python`, …) into a **single** `apache-ua-keywords` jail/filter. Same rules, far fewer file watches.
- `update-useragent-jails.sh` and `generate-logpath.sh` updated so WHM regenerates keep the combined jail + pyinotify.
- Install/update now require/install `python3-inotify`, remove legacy per-keyword UA configs, and regenerate the combined UA jail.

### Other
- Ship default `conf.d/useragent-keywords.conf` (created only if missing, so user edits are preserved).
- Skip `*-bytes_log` files when building excluded-domain logpath lists.
- WHM plugin version bump to 1.0.7.

## [1.0.6] - 2026-08-17

- Country-scoped CMS/editor path allow list in WHM.
