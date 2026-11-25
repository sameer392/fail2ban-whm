# Changelog

## [Unreleased]

### Performance
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
