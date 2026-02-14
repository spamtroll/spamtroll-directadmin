# Changelog

All notable changes to the DirectAdmin Plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Professional README.md with installation, configuration, and usage documentation
- MIT License
- **W6**: Pluggable menu support for DirectAdmin Evolution skin (images/menu.json)
- **W7**: Added version_url to plugin.conf for automatic update checking
- **M4**: Added logrotate configuration for /var/log/spamtroll.log
- Hourly activity bar chart on Dashboard (24h, safe/blocked breakdown)
- Whitelist/blacklist functionality — bypass or block emails by sender/domain
- Manual email content test from admin panel Settings
- API usage/quota display after successful connection test
- CSV export of statistics from Dashboard
- Log filtering by text search and status (All/Blocked/Safe/Error)
- Auto-refresh for log viewer (10s interval, state persisted in URL)
- Button loading states with "Processing..." feedback
- Confirmation dialog when disabling spam filtering

### Fixed
- **K1**: Added CSRF token protection to admin panel forms (DirectAdmin requirement)
- **K2**: Moved config file from /etc/spamtroll.conf to plugin data directory (fixes permission issue — admin panel runs as diradmin, not root)
- **K3**: Replaced PHP superglobals with DA environment parsing (parse_str/getenv) for CGI compatibility
- **W1**: Fixed potential XSS in score display (added htmlspecialchars)
- **W2**: Fixed lastEntries collecting oldest instead of newest log entries
- **W3**: Moved stats cache from world-readable /tmp to plugin data directory
- **W4**: Replaced `systemctl restart exim` with `da build exim_conf` for proper DA integration
- **W5**: Added ACL backup in update.sh before overwriting
- **W9**: Replaced unsafe `source` config loading with safe key=value parsing in spamtroll-check
- **W10**: Added body size limit in Exim ACL configuration
- **M3**: Fixed regex patterns for parsing quoted config values
- **M5**: Added API key format validation on save
- Server-side CSRF token validation (was only in forms, not verified on POST)
- Logrotate config now installed/removed/updated by lifecycle scripts
- SpamtrollAPI CGI compatibility ($_SERVER → getenv for REMOTE_ADDR)

### Changed
- Config file location: /etc/spamtroll.conf → plugin/data/spamtroll.conf
- Config permissions: 600 root:root → 660 diradmin:diradmin
- Log file permissions: 644 → 640 root:diradmin
- Build script excludes dev files and unused assets from distribution
- Recent Activity shows 25 entries (was 10)
- System Information shows file size, permissions, and modification date
- SpamtrollAPI reactivated for email testing and usage checks

### Removed
- Orphan WordPress uninstall.php (referenced $wpdb, WP_UNINSTALL_PLUGIN)
- Dead JavaScript for CSRF token fetch (guard always exited early)
- Removed DA-managed fields from plugin.conf (installed, *_script)

## [0.1.0] - 2026-02-04

### Added
- DirectAdmin plugin for Spamtroll spam detection integration
- Moved from root directory to `integrations/directadmin-plugin/`
