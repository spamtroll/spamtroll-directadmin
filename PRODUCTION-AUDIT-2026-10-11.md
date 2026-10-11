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
