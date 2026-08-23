# Changelog

All notable changes to the DirectAdmin Plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- **API key no longer reaches `argv`** (`exim/spamtroll-check`). The key was passed to `curl` as `-H "X-API-Key: …"`, once per delivered message; `/proc/<pid>/cmdline` is world-readable on a stock DirectAdmin install, so any shell user on a shared server could read the owner's key out of `ps`. It now travels over a curl config file on a pipe (`-K <(…)`). The message payload moved out of `curl -d` and `jq --arg` into `jq`'s environment for the same reason — `/proc/<pid>/environ` is 0400.
- **Stored XSS in the admin dashboard, triggered by a remotely sent email.** `admin/index.html` echoed `strtoupper($entry['status'])` unescaped. `status` is parsed back out of the plugin's own log line, which is built from message headers, so a `To:` header shaped like `x" status="<svg onload=alert(1)>" y="` injected a `status` field the parser preferred, executing script in the DirectAdmin admin's session. Two independent fixes: `spamtroll-check` strips quotes, backslashes, newlines and control characters from every value it logs, and the panel maps the verdict through a fixed table so only `BLOCKED`/`SUSPICIOUS`/`SAFE`/`ERROR`/`UNKNOWN` can be rendered. Remaining unescaped `<?=` sinks (message type, chart titles, config paths) were escaped as well.
- **`accept` at the top of the Exim ACL disabled DirectAdmin's own scanning.** The file is included at the start of `acl_check_message`, and `accept` ends evaluation of the whole ACL — so ClamAV (`malware = *`), SpamAssassin, outbound limits and any admin rules were skipped for all authenticated SMTP and all loopback-submitted mail. Replaced with negative conditions on the `warn` verb, which lets evaluation continue.
- **Argument splitting hardened against sender-controlled quotes** (W8). Message-derived values are passed base64-encoded behind a one-letter marker: the base64 alphabet has no whitespace or quotes, and the marker keeps every argument non-empty. Verified against Exim 4.98.2 that the previous `"${sg{$h_subject:}{\\n}{}}"` form splits `Re: "pilne" sprawy` into three arguments under `${run,preexpand}` and shifts every later argument, while the base64 form is stable under both preexpand and the modern split-then-expand default.
- **`Authentication-Results` is no longer forwarded to the API.** On a directly receiving MTA every copy of that header arrived with the message, and the backend grants a negative (ham) score for any `spf=pass` / `dmarc=pass` substring in it — handing the sender a switch for lowering their own score. DKIM is now covered properly by `raw_message`.
- `TIMEOUT` and `API_KEY` are validated before being written into the curl config file, so a hand-edited config file cannot inject curl options. The `API_URL` value stored in the config file is now genuinely ignored, as the comment above it always claimed — honouring it turned a config write into an API-key exfiltration primitive.
- Explicit `CURLOPT_SSL_VERIFYPEER` / `CURLOPT_SSL_VERIFYHOST`, `CURLOPT_FOLLOWLOCATION => false` and an https-only protocol restriction in `lib/api.php` and `lib/config.php`; `--proto '=https'` in `spamtroll-check`.

### Fixed
- **The spam verdict was unreachable — the filter marked nothing.** `${run{…}{$runrc}{2}}` expands its *second* branch for every non-zero exit code, so `exit 1` (blocked) produced the literal `"2"` and the rule adding `X-Spamtroll-Status: spam` was dead code. The run item now yields `$runrc/$value`, carrying both the exit code and the score.
- **Plugin updates were a no-op on the Exim ACL.** `install.sh` symlinks `/usr/local/bin/spamtroll-check` at the copy inside the plugin directory; `update.sh` then ran `cp` onto that symlink, i.e. the file onto itself. GNU `cp` refuses and exits 1, and `set -e` ended the script before the ACL, logrotate and Exim rebuild. `update.sh` now re-links the way `install.sh` does, sets `pipefail`, adds the missing `chown root:root` on the ACL and an `ERR` trap so a failure is visible in DirectAdmin.
- **`uninstall.sh` deleted the admin's own Exim rules.** `/etc/exim.acl_check_message.pre.conf` is a documented DirectAdmin extension point, not a file owned by this plugin. It now restores the newest backup that does not contain our own ACL, and only removes the file when there is no pre-install backup.
- **Only ~500 bytes of the body were ever scanned.** `$message_body` is capped by the main option `message_body_visible` (default 500), which cannot be set from an ACL file, so `substr{0}{50000}` and `MAX_BODY_SIZE` were dead code. The body is now read from the spool `-D` file, which Exim has flushed and fsynced before the DATA ACL runs.
- **Body and subject reached the API still MIME-encoded**, so `content_analysis`, `bayes` and `retvec` scored base64 and quoted-printable noise — a large part of the false-positive rate on Polish mail. The body is MIME-decoded with `python3`'s `email` package when available (raw wire form otherwise). The subject was already RFC 2047-decoded by Exim's `$h_subject:`; that is now stated in the ACL rather than worked around.
- **`raw_message` is now sent**, so the backend runs a real RFC 6376 cryptographic DKIM verification instead of the weak "a `DKIM-Signature` header exists and its `d=` aligns" fallback, which a sender can fake by pasting a header. Omitted, deliberately, when the reconstructed message is not 7-bit clean or exceeds 120 KB — `jq` substitutes U+FFFD for invalid UTF-8, and a `raw_message` that fails verification is worse than none because it suppresses the header-only fallback.
- **`List-Unsubscribe`, `List-Id` and `Precedence` are now sent** — the `sender_context` stage reads all three, and without them newsletters and transactional mail never got their symbol.
- **`suspicious` was reported as `clean`.** It now has its own exit code and its own `X-Spamtroll-Status: suspicious` header. Exit code 2, which the script documented but never returned, now covers every no-verdict path (quota exhausted, non-2xx, unparseable body, plugin disabled), so those messages pass through unmarked instead of being stamped `clean`.
- **`lib/api.php` returned the boolean `true` as an error message.** The rate limiter and Fiber's error handler both reply `{"error": true, "message": "…"}`, so the panel showed `Test failed: 1`. All four documented error-body shapes are now reduced to one, keeping the application code and the 402 `usage` block that was being discarded, with a per-status fallback for uninformative bodies (401 and 403 are distinguished).
- **"Test connection" always failed.** `SpamtrollConfig::testConnection()` built its URL with `str_replace('/scan/check', …)` on a value that has held the base URL since `api_url` was pinned, so every test requested `/api/v1` and told admins with a perfectly good key "API returned HTTP 404".
- Config parser now trims whitespace around values, so a hand-written `ENABLED = true` no longer silently disables the plugin.
- Added the missing `.alert-warning` CSS class used by the quota banner.
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

### Added
- `X-Spamtroll-Score` header, carrying the numeric score the ACL comment has been promising. The value can only be what a numeric regex captured, so nothing from the message can reach a header.
- `tests/run-tests.sh` — 39 assertions over the exit-code contract, the fail-open guarantee on every error path (402, 429, 401, 403, HTML error pages, empty and unparseable bodies, curl failures, timeouts, unconfigured plugin), argv hygiene and payload shape. Stubs `curl`, so it touches neither the network nor an installed plugin.
- `tests/api-error-shapes.php` — 13 assertions over the four API error-body shapes.
- **Quota-aware fail-open** in the Exim ACL hook (`exim/spamtroll-check`). The script now captures the HTTP status code via `curl -w "\n%{http_code}"`; when the API returns 402 the script appends a one-line entry to `${LOG_DIR}/quota_skipped.log`, logs at WARN, and exits 0 (accept the message without scanning). Blocking legitimate mail because the user's plan ran out of paid scans was the wrong call.
- Admin panel now reads `quota_skipped.log` and shows a warning banner with the trailing-7-day count, the most recent timestamp, and an "Upgrade your plan →" CTA. Hidden when there are no entries in the window so a healthy account doesn't see it.
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

### Changed
- Messages the plugin could not get a verdict for no longer receive `X-Spamtroll-Status: clean`. They now arrive with no `X-Spamtroll-*` header at all. Sieve/Procmail rules that treated a missing header as suspicious need to be aware of this; the plugin remains fail-open in every case.
- `README.md` now describes what the ACL actually does: header-only verdicts, no `deny`/`defer`, and the fact that skipping outbound mail applies to the Spamtroll check only, not to DirectAdmin's ClamAV and SpamAssassin.
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
