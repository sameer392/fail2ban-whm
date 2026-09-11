# Changelog

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
