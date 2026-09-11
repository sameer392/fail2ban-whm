# Operations

## Management Commands

```bash
# Service status
fail2ban-client status

# Per-jail status
fail2ban-client status wordpress-wp-login
fail2ban-client status apache-high-volume

# List banned IPs
fail2ban-client get wordpress-wp-login banip

# Unban an IP
fail2ban-client set wordpress-wp-login unbanip <IP_ADDRESS>

# Monitor log
tail -f /var/log/fail2ban.log

# Verify domlog path
ls /usr/local/apache/domlogs/*/* | head -5

# Status script
/usr/share/fail2ban/scripts/status.sh
```

---

## Shell Scripts Reference

| Script | Purpose |
|--------|---------|
| install.sh | Full install: copy to /usr/share/fail2ban, deploy, IP2Location, logrotate, enable, WHM plugin |
| update.sh | Deploy config to /etc/fail2ban (backs up first), restart fail2ban; updates WHM plugin (no cPanel restart) |
| update-from-github.sh | Update from GitHub release. Usage: `update-from-github.sh <tag>` (e.g. `v1.0.1`). Uses auto-generated source archive. |
| restore-backup.sh | Restore from backup (default: latest). Usage: `restore-backup.sh [BACKUP_DIR]` |
| uninstall.sh | Remove config; --purge = also packages, WHM plugin, /etc and /usr/share |
| status.sh | Show fail2ban service and jail status |
| update-whitelist.sh | Regenerate filter ignoreregex from whitelist-ips.conf |
| cms-allow.sh | Country-scoped CMS/editor path allow (ignorecommand + helper for csf-ban.sh) |

All scripts must be run as root.

---

## Logging and Rotation

| Item | Details |
|------|---------|
| **Log file** | `/var/log/fail2ban.log` |
| **Logrotate** | `/etc/logrotate.d/fail2ban` – rotate at 50MB or weekly, keep 4 compressed archives |
| **Flush** | Uses `fail2ban-client flushlogs` so no restart needed |
| **Immediate rotate** | `logrotate --force /etc/logrotate.d/fail2ban` |
| **Loglevel** | `fail2ban.d/loglevel-verbose.conf` – set INFO for more detail, WARNING for less. Remove file to use fail2ban default. |

### Backup & Restore

`update.sh` creates a timestamped backup in `/etc/fail2ban/backups/YYYYMMDD-HHMMSS/` before each deploy (keeps last 10). To restore: `scripts/restore-backup.sh` (latest) or `scripts/restore-backup.sh /etc/fail2ban/backups/YYYYMMDD-HHMMSS`.

---

## Creating a Release (maintainers)

1. Bump `FAIL2BAN_WHM_VERSION` in `whm-plugin/plugin/index.php` and add a `CHANGELOG.md` section.
2. Commit, tag, and push:
   ```bash
   git tag v1.0.8 && git push origin main && git push origin v1.0.8
   ```
3. Pushing a `v*` tag runs `.github/workflows/release.yml`, which creates the GitHub Release (WHM “Check for updates” reads `/releases/latest`) and attaches `install.sh`. If that tag already has a release (for example after moving the tag), the workflow updates it instead of failing.
4. GitHub also auto-generates the source archive at `https://github.com/sameer392/fail2ban-whm/archive/refs/tags/v1.0.8.zip`
5. Users update via WHM (Update tab) or `update-from-github.sh v1.0.8`

A GitHub **Release** (not only a git tag) is required for WHM and `install.sh` to see the new version.

---

## Applicability

This configuration protects **all** sites on the server. The log path `/usr/local/apache/domlogs/*/*` covers all cPanel domain logs (primary and addon domains).
