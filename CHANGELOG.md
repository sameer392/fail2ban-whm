# Changelog

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
