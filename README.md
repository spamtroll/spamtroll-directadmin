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

1. Download the latest `plugin.tar.gz` from [spamtroll.io/directadmin/plugin.tar.gz](https://spamtroll.io/directadmin/plugin.tar.gz)
2. Go to **DirectAdmin > Plugin Manager**
3. Click **Upload Plugin** and select the file
4. The installer will set up all components automatically

### SSH / Command Line

```bash
cd /usr/local/directadmin/plugins
wget https://spamtroll.io/directadmin/plugin.tar.gz
tar -xzf plugin.tar.gz
cd spamtroll
./scripts/install.sh
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
/usr/local/bin/spamtroll-check
     |
     v
Spamtroll API (RETVec + GPT analysis)
     |
     +---> spam detected  ---> REJECT (550)
     +---> clean          ---> ACCEPT + X-Spamtroll-Status: clean
     +---> API error      ---> ACCEPT (fail-open)
```

Authenticated users and trusted relay hosts bypass the check entirely.

## Admin Panel

The admin panel is accessible at **DirectAdmin > Spamtroll Anti-Spam** (admin-level only).

- **Dashboard** -- 24h email statistics (total, blocked, safe), recent activity, and top blocked domains
- **Settings** -- Enable/disable filtering, API key, API URL, log level, timeout, and connection test
- **Logs** -- Real-time log viewer with color-coded entries (blocked, safe, error)

## Updating

### Automatic

If `version_url` is configured in `plugin.conf`, DirectAdmin will check for updates automatically and notify the admin.

### Manual

```bash
cd /usr/local/directadmin/plugins
wget -O plugin.tar.gz https://spamtroll.io/directadmin/plugin.tar.gz
tar -xzf plugin.tar.gz
cd spamtroll
./scripts/update.sh
```

The update script preserves your configuration and creates a backup of the Exim ACL before overwriting.

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

Log format:
```
2026-02-04 12:34:56 [info] from=sender@example.com ip=1.2.3.4 status=blocked score=0.95
```

Log rotation is handled by `/etc/logrotate.d/spamtroll` (daily, 30 days retention, compress).

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
- Test connectivity: `curl -s https://api.spamtroll.io/api/v1/scan/check`
- Verify your API key at [spamtroll.io/dashboard](https://spamtroll.io/dashboard)
- Check timeout setting (increase if network is slow)

**Permission errors in admin panel**
- Config file should be owned by `diradmin:diradmin` with mode `660`
- Log file should be owned by `root:diradmin` with mode `640`

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

## Support

- Website: [spamtroll.io](https://spamtroll.io)
- Email: [support@spamtroll.io](mailto:support@spamtroll.io)
- Issues: [GitHub Issues](https://github.com/spamtroll/directadmin-plugin/issues)

## License

[MIT](LICENSE)
