# Spamtroll Anti-Spam for DirectAdmin

AI-powered spam detection plugin for [DirectAdmin](https://www.directadmin.com/) hosting panel. Integrates with [Spamtroll](https://spamtroll.io) to scan incoming emails in real-time using machine learning (RETVec + GPT).

## Features

- **Real-time email scanning** via Exim ACL integration
- **AI-powered detection** using RETVec and GPT models
- **Admin panel** with Dashboard, Settings, and Logs tabs
- **24h statistics** with top blocked domains overview
- **Fail-open design** -- emails are accepted if the API is unreachable
- **CSRF and XSS protection** in the admin interface
- **Automatic log rotation** via logrotate
- **Auto-updates** via DirectAdmin Plugin Manager

## Requirements

- DirectAdmin >= 1.60.0
- Exim (included with DirectAdmin)
- `curl`, `jq` (auto-installed if missing)
- Spamtroll API key ([get one here](https://spamtroll.io/dashboard))

## Installation

### DirectAdmin Plugin Manager (Recommended)

1. Download the latest [DirectAdmin plugin archive](https://spamtroll.io/download/spamtroll-directadmin.tar.gz)
2. Go to **DirectAdmin > Plugin Manager**
3. Click **Upload Plugin** and select the file
4. The installer will set up all components automatically

### SSH / Command Line

```bash
(
set -eu
archive=$(mktemp /tmp/spamtroll-directadmin.XXXXXX)
trap 'rm -f "$archive"' EXIT
mkdir -p /usr/local/directadmin/plugins/spamtroll
cd /usr/local/directadmin/plugins/spamtroll
curl -fL https://spamtroll.io/download/spamtroll-directadmin.tar.gz -o "$archive"
tar -xzf "$archive"
./scripts/install.sh
)
```

## Configuration

### Admin Panel

1. Go to **DirectAdmin > Spamtroll Anti-Spam**
2. Navigate to the **Settings** tab
3. Enter your API key and enable spam filtering
4. Click **Save Configuration**

### Manual (config file)

Edit `/usr/local/directadmin/plugins/spamtroll/data/spamtroll.conf`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ENABLED` | `false` | Enable/disable spam filtering |
| `API_KEY` | _(empty)_ | Your Spamtroll API key |
| `API_URL` | `https://api.spamtroll.io/api/v1/scan/check` | API endpoint |
| `LOG_LEVEL` | `info` | Logging verbosity: `debug`, `info`, or `error` |
| `TIMEOUT` | `5` | API request timeout in seconds |

After manual changes, rebuild Exim config:

```bash
cd /usr/local/directadmin && ./directadmin build exim_conf
```

## How It Works

```
Incoming Email
     |
     v
Exim ACL (acl_check_message.pre.conf)
     |
     v
/usr/local/bin/spamtroll-check   (headers from the ACL, body from the spool)
     |
     v
Spamtroll API (RETVec + GPT analysis)
     |
     +---> blocked     ---> ACCEPT + X-Spamtroll-Status: spam       + X-Spamtroll-Score
     +---> suspicious  ---> ACCEPT + X-Spamtroll-Status: suspicious + X-Spamtroll-Score
     +---> safe        ---> ACCEPT + X-Spamtroll-Status: clean      + X-Spamtroll-Score
     +---> no verdict  ---> ACCEPT, no header at all
```

**The plugin never rejects or defers a message.** The ACL contains no
`deny` and no `defer`: verdicts are published as headers and users route
on them with Sieve, Procmail or IMAP filters. Anything that is not a
verdict — API outage, exhausted quota, HTTP error, missing script —
leaves the message with no `X-Spamtroll-*` header at all, rather than
claiming it is clean. Losing correspondence to a filter outage is worse
than letting spam through.

Authenticated SMTP submissions and mail injected over loopback
(Roundcube, `sendmail`, cron) are not sent to Spamtroll. They still go
through everything else DirectAdmin puts in the DATA ACL — ClamAV,
SpamAssassin, outbound limits.

## Admin Panel

The admin panel is accessible at **DirectAdmin > Spamtroll Anti-Spam** (admin-level only).

- **Dashboard** -- 24h email statistics (total, blocked, safe), recent activity, and top blocked domains
- **Settings** -- Enable/disable filtering, API key, whitelist/blacklist, connection test, and a manual content test (API URL, log level and timeout are pinned to safe defaults and not user-editable)
- **Logs** -- Real-time log viewer with color-coded entries (blocked, safe, error)

## Testing

```bash
./tests/run-tests.sh          # exit-code contract, fail-open on every error path,
                              # argv hygiene, payload shape (needs bash 4+, jq)
php tests/api-error-shapes.php  # the four API error-body shapes
```

`tests/run-tests.sh` stubs `curl`, so it never touches the network and
never touches an installed plugin. It needs bash 4+; on macOS run it
under a container.

### CI gates

Every push and pull request to `main` runs `.github/workflows/qa.yml`.
The plugin installs as root and sits in Exim's DATA path. The frontend image
fetches an explicitly versioned GitHub release and verifies its SHA-256;
its deployed image serves the archive and matching version file under
`/download/`. Publishing source to `main` alone does not update that channel.
The deployed release is 1.1.3; changing it requires updating the frontend's
release/checksum pins and deploying the verified image.

The gates live in `tests/ci/` rather than in `run:` blocks, so each one can be
reproduced locally with a single command:

```bash
./tests/ci/assert-suite.sh    # run-tests.sh, but a skipped test is a failure
./tests/ci/version-gate.sh    # plugin.conf == CHANGELOG == admin panel
sudo ./tests/ci/acl-gate.sh   # exim -bV, fail-open grep, 8 x exim -bh
```

`acl-gate.sh` needs Exim and uses a temporary scanner stub, configuration and
spool path. It never overwrites the installed scanner. Some DirectAdmin Exim
builds restrict alternative configuration paths; use a disposable container
for this gate rather than changing production Exim security settings:

```bash
docker run --rm -v "$PWD:/src:ro" ubuntu:24.04 bash -c '
  apt-get update -qq && apt-get install -y -qq exim4-daemon-light
  cp -r /src /work && cd /work && ./tests/ci/acl-gate.sh'
```

The remaining gates — ShellCheck `-S style`, `php -l` on 8.1 and 8.4, PHPStan
level 5 (`phpstan.neon`), the AlmaLinux 8 run of the suite, and the tarball
shape assertions — are defined inline in the workflow.

`sudo bash tests/log-permissions.sh` tests the installer, updater and real
logrotate against a temporary filesystem fixture. It requires Linux,
`python3`, `logrotate`, and the `admin` user and `mail` group. DirectAdmin's
rebuild command is stubbed; no mail service is restarted by the fixture.

Production audit and verified native update: [nawia, 2026-10-11](PRODUCTION-AUDIT-2026-10-11.md#deployment-addendum--2026-10-11-t-071).

## Updating

### Automatic

DirectAdmin periodically checks `version_url` from `plugin.conf` and shows
available updates in Plugin Manager. The native update action downloads
`update_url`, extracts it directly into the installed plugin directory and
runs `scripts/update.sh`. Version 1.1.3 was deployed through this native
mechanism on `nawia`; detection and the update action were verified. This
verification did not add an unattended update schedule.

### Manual

```bash
(
set -eu
archive=$(mktemp /tmp/spamtroll-directadmin.XXXXXX)
trap 'rm -f "$archive"' EXIT
cd /usr/local/directadmin/plugins/spamtroll
curl -fL https://spamtroll.io/download/spamtroll-directadmin.tar.gz -o "$archive"
tar -xzf "$archive"
./scripts/update.sh
)
```

The update script preserves your configuration and creates a backup of the Exim ACL before overwriting.
Back up the complete plugin and integration before updating. The archive has
`plugin.conf` at its root and excludes `data/`, preserving configuration and
directory permissions during native DirectAdmin extraction.

## Uninstallation

Via DirectAdmin Plugin Manager, or manually:

```bash
cd /usr/local/directadmin/plugins/spamtroll
./scripts/uninstall.sh
```

**Removed:**
- `/usr/local/bin/spamtroll-check`
- `/etc/exim.acl_check_message.pre.conf`

**Preserved (for potential reinstall):**
- Configuration file (`data/spamtroll.conf`)
- Log file (`/var/log/spamtroll.log`)

## Log Files

| File | Description |
|------|-------------|
| `/var/log/spamtroll.log` | Main log -- scan results, errors |
| `/var/log/spamtroll/quota_skipped.log` | Messages left unscanned after HTTP 402 |

Log format:
```
2026-02-04 12:34:56 [info] from=sender@example.com ip=1.2.3.4 status=blocked score=0.95
```

Both logs rotate weekly, keeping 12 rotations, with delayed compression.
New files are owned by `admin:mail` with mode `0660`, allowing the panel and
Exim to append after rotation. Version 1.1.3 repairs older log permissions
during installation or update without removing existing entries.

## Troubleshooting

**Plugin shows as disabled in DirectAdmin**
- Verify `active=yes` in `plugin.conf`
- Check DirectAdmin Plugin Manager for errors

**Emails are not being checked**
- Ensure `ENABLED=true` and `API_KEY` is set in the config file
- Verify the Exim ACL file exists: `ls -la /etc/exim.acl_check_message.pre.conf`
- Check that `spamtroll-check` is installed: `which spamtroll-check`
- Rebuild Exim config: `cd /usr/local/directadmin && ./directadmin build exim_conf`

**API connection fails**
- Use the panel's connection test, which calls the authenticated `/scan/status` endpoint
- Verify your API key at [spamtroll.io/dashboard](https://spamtroll.io/dashboard)
- Check timeout setting (increase if network is slow)

**Permission errors in admin panel**
- Configuration directory should be owned by `admin:mail` with mode `750`; the configuration file must be readable by `mail` and writable by `admin` (`640`, or `660` after a panel save)
- Main and quota-skipped logs should be owned by `admin:mail` with mode `660`

## File Structure

```
/usr/local/directadmin/plugins/spamtroll/
|-- plugin.conf              # Plugin metadata
|-- admin/
|   `-- index.html           # Admin panel (PHP/CGI)
|-- assets/
|   `-- spamtroll-logo.svg   # Logo
|-- data/
|   |-- spamtroll.conf       # Runtime configuration
|   `-- cache/               # Stats cache
|-- exim/
|   |-- acl_check_message.pre.conf  # Exim ACL rules
|   |-- spamtroll-check      # Email check script
|   `-- spamtroll-logrotate  # Logrotate config
|-- hooks/
|   `-- admin_txt.html       # DA hook for admin menu
|-- images/
|   |-- admin_icon.svg       # Menu icon
|   `-- menu.json            # Evolution skin menu
|-- lib/
|   |-- api.php              # API client library
|   |-- config.php           # Configuration manager
|   `-- stats.php            # Statistics collector
`-- scripts/
    |-- install.sh           # Installation script
    |-- uninstall.sh         # Uninstallation script
    `-- update.sh            # Update script
```

Development-only files — `tests/`, `.github/`, `phpstan.neon` — are not copied
into the tarball, and the Package gate asserts that they never appear in it.

## Support

- Website: [spamtroll.io](https://spamtroll.io)
- Email: [support@spamtroll.io](mailto:support@spamtroll.io)
- Issues: [GitHub Issues](https://github.com/spamtroll/directadmin-plugin/issues)

## License

[MIT](LICENSE)
