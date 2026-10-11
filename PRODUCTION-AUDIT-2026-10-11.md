# DirectAdmin production audit — 2026-10-11

## Recommendation

Update the installation on `nawia.hostpark.pl` from 1.0.0 to the prepared
1.1.3 package. The installed version has reproducible problems; the source
at 1.1.2 already addresses most, while 1.1.3 fixes log ownership after
rotation and provisions the quota-skipped log.

This audit tested production credentials and the production Exim binary
using isolated fixtures. The installed plugin, configuration, live ACL,
mail queue and service were not changed. No real recipient received a
test message. Version 1.1.3 is prepared locally, not published by this task.

## Installed environment and findings

- DirectAdmin 1.712, Exim 4.100.1, PHP CLI 8.4.26; plugin metadata 1.0.0.
- Scanning is enabled and a key is configured. Exim can read the settings;
  the key works with the corrected API client.
- The installed panel's connection test returns HTTP 404. The maintained
  client calls `/scan/status` and returns HTTP 200 with the same key.
- The main log is `root:diradmin`, mode `0640`; neither `mail` nor `admin`
  can append. Its empty contents cannot prove that scanning is disabled.
  The installed and previously maintained logrotate configuration causes
  this failure again after rotation.
- The installed ACL uses `accept` for authenticated and local mail, ending
  the entire DATA ACL before subsequent DirectAdmin checks. It also uses
  the old argument contract and colon-separated IPv6 loopback exclusion.
  The maintained ACL excludes those scans through conditions on `warn`,
  leaving later checks reachable.
- The installed scanner has older error handling, argument quoting and
  credential handling. The maintained scanner distinguishes no verdict
  from a clean result, handles suspicious verdicts, and keeps the API key
  out of curl arguments. Verdicts only add headers; they never reject mail.
- Exim was active and its queue was empty before and after the tests.

## Verification of prepared 1.1.3

- All 39 scanner regression assertions passed without skips on Debian
  Linux and on the production host against a staged source copy.
- All 13 PHP API error-shape assertions passed. PHPStan level 5, ShellCheck
  0.10.0, shell syntax and version consistency checks passed.
- Installer/updater fixture: preserved configuration bytes, preserved old
  log contents, repaired write access for both users, handled a repeated
  update, rotated both logs with real logrotate, and provisioned a fresh
  disabled installation. The actual DirectAdmin rebuild was stubbed.
- Eight Exim SMTP simulations covered clean/spam/suspicious, scanner error,
  missing scanner, abnormal exit and both loopback addresses. All accepted
  the synthetic message and reached the following DATA ACL rule.
- The production binary restricts `-C` paths. Tests used a private mount
  namespace to bind the fixture over the default configuration only for
  the test process; host configuration hashes stayed unchanged.
- A staged scanner run as `mail` obtained `safe`, score `1`, from the real
  API. A full synthetic SMTP simulation using the staged ACL and scanner
  added `X-Spamtroll-Status: clean`, score `1`, reached the following ACL
  rule and accepted the message without queueing or delivering it.

## Deployment and rollback requirements

Before a later deployment, take a root-only backup of the entire plugin
including `data`, the installed scanner/symlink, live ACL, logrotate file
and their ownership/modes. Record the configuration digest, Exim status
and queue count. Preserve the current `data` directory when replacing code.

The updater rewrites the plugin ACL and invokes DirectAdmin's Exim rebuild.
Review any local ACL changes before applying it. Verify configuration
syntax, service health, connection test and a synthetic scanner/SMTP test
afterward; compare the configuration digest and test log writes as both
`mail` and `admin`. Native Plugin Manager update and interactive panel
rendering were not exercised by this audit.

If verification fails, restore the backed-up plugin code, ACL, scanner link
and logrotate file, preserving configuration and any newly written logs;
validate Exim configuration before reloading the service. No rollback was
needed or performed during this read-only production audit.

## Deployment addendum — 2026-10-11 (T-071)

The historical audit above records the preparation phase of T-070. T-071
subsequently published and deployed **1.1.3** on `nawia`; its recommendation
to update from 1.0.0 is now fulfilled.

- [Release v1.1.3](https://github.com/spamtroll/spamtroll-directadmin/releases/tag/v1.1.3)
  targets runtime commit `3c5752b`. All seven QA jobs passed (run
  `38167142924`), as did release publication (`38167234994`) and the frontend
  build/deployment checks (`38167319055`). The public archive SHA-256 is
  `787004a178feae3a55f689ab3b27927549e2e0bd2ecf08d9f733c4b8e1d1d685`.
- The archive has `plugin.conf` at its root and excludes `data/`. The old
  enclosing directory caused native extraction to leave active code unchanged;
  the corrected flat package was tested before deployment. The frontend now
  serves explicitly pinned, checksum-verified release assets.
- The actual DirectAdmin Plugin Manager update API returned HTTP 204 and ran
  the new `scripts/update.sh`. All 17 runtime files matched the release;
  DirectAdmin's metadata normalization of `plugin.conf` was expected. Installed
  and available versions both reported 1.1.3 after a controlled panel restart
  cleared its stale version cache. No unattended update schedule was added.
- Configuration bytes and the active flag were preserved. Settings stayed
  `0640 admin:mail`, the data directory `0750 admin:mail`, and both logs
  `0660 admin:mail`. The live panel and API connection test returned HTTP 200.
  The scanner as `mail` returned safe/score 1 before and after real plugin-only
  log rotation; both `mail` and `admin` retained log write access.
- A synthetic SMTP check through the installed ACL/scanner and real API reached
  the following ACL rule and accepted the message without queueing or delivery.
  Exim configuration validation passed, DirectAdmin and Exim remained healthy,
  and the queue was empty. The temporary test credential was revoked and its
  subsequent request returned HTTP 401.

Root-only backups and their verified checksum manifest remain under
`/var/backups/spamtroll/T-071-codex-7251/`, including `ROLLBACK.md`.
Rollback restores prior code/integration while retaining current settings and
new log entries, validates Exim configuration, then reloads and checks health.
No rollback was needed. This addendum reports T-071's verified deployment;
editing these documents does not redeploy or modify the server.
