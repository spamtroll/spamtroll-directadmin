# DirectAdmin plugin submission preparation

The Spamtroll DirectAdmin plugin provides incoming-email spam scoring and Exim verdict headers. This document contains a listing draft and the preparation record for a future catalogue submission. It is not evidence that a submission or publication has taken place.

## Listing draft

| Field | Value |
| --- | --- |
| Name | Spamtroll Anti-Spam |
| Plugin ID | spamtroll |
| Publisher | Spamtroll.io |
| Website | https://spamtroll.io |
| Source and issue tracker | https://github.com/spamtroll/spamtroll-directadmin |
| Support contact declared in plugin.conf | support@spamtroll.io |
| License | MIT; see LICENSE |
| Publicly served version checked on 4 October 2026 | 1.1.1 |
| Download URL | https://spamtroll.io/download/spamtroll-directadmin.tar.gz |
| Version URL | https://spamtroll.io/download/spamtroll-directadmin.version |
| Update URL | Same as download URL, as declared in plugin.conf |
| Installation requirements | DirectAdmin 1.60+, Exim, Bash 4+, PHP CLI for the admin UI, curl, jq and an active Spamtroll API key |
| Access level | Administrator |

**Short description:** Score incoming email through the Spamtroll API and add verdict headers to Exim messages. Configure filtering in the administrator panel and route messages using your existing mail rules.

**Full description:** Spamtroll integrates with Exim's DATA ACL to analyse incoming email using the Spamtroll service. The service combines reputation, rules and configured machine-learning/AI stages. The plugin adds `X-Spamtroll-Status` and `X-Spamtroll-Score` headers when a valid verdict is available. Administrators can configure the API key, enable scanning, manage lists, test connectivity and inspect recent activity.

The plugin itself never rejects or defers messages, including messages classified as spam. Mail routing based on its headers is configured separately by the customer. API errors, exhausted quota and missing verdicts leave messages without Spamtroll headers; they are not falsely marked clean. Authenticated SMTP and loopback submissions are skipped. This plugin does not replace the rest of DirectAdmin's mail security checks.

The plugin software uses the MIT license. The hosted scanning service requires an account and API key; do not describe the service as unlimited or free without checking the current published plan. No availability, accuracy or independent certification claims are made by this draft.

## Package preparation

DirectAdmin documents the plugin directory, `plugin.conf` metadata, administrator entry point, lifecycle scripts and executable permissions in its [plugin structure specification](https://docs.directadmin.com/developer/plugins/structure.html). These are technical installation requirements, not confirmed catalogue acceptance rules.

The distribution is built with `bash build.sh`, producing `plugin.tar.gz` with the `spamtroll/` top-level directory. The release workflow renames this archive to the filename declared by `update_url`, produces the plain-text version file and publishes checksums. The frontend delivery build serves these files; a local build or GitHub artifact does not update the public download automatically.

The packaging changes under Unreleased include LICENSE, README.md and CHANGELOG.md. The existing CI package gate checks those files along with runtime entry points and executable bits. Local artifacts containing these changes must not be described as byte-identical to the currently served public 1.1.1 package. Establish the release version and publish through the existing delivery process before submitting a final archive URL.

The current public package downloaded on 4 October 2026 contained version 1.1.1 and omitted those three documents. The local packaging correction has not yet been deployed to that URL.

Local checks on 4 October 2026 passed: 39 scanner regressions with no skips on Linux, 13 PHP API error-shape checks, version consistency, ShellCheck on the changed build script, and the existing package CI gate including contents and executable permissions. The three packaged documents and plugin metadata were compared byte-for-byte with the source. No current licensed DirectAdmin installation was exercised by these local checks.

## Submission record and remaining requirements

As of 4 October 2026, no submission was sent and no catalogue approval was obtained. The task's destination, `plugins.directadmin.com`, did not resolve through the local resolver. A public DNS A query returned no addresses; this does not establish that the domain was removed or that no alternative catalogue exists. No current official submission form or acceptance policy was identified. A current publication route and account access are required.

Before submission:

1. Confirm the current catalogue URL, account and actual acceptance rules. Do not assume the historical task URL is usable.
2. Apply any catalogue-specific fields or screenshot requirements once they are known; do not claim compliance with unknown rules.
3. Decide and publish the release that includes the licensing/package fixes, then fetch its public archive and compare version, contents and checksums.
4. Obtain evidence on a supported DirectAdmin/Exim installation for the version submitted. Existing syntax, behavior and ACL simulation tests are useful but do not constitute a current installed-system certification.
5. Review this listing against the published package, pricing and actual catalogue fields, then submit through the authenticated publication path.
6. Record the submission URL/identifier, timestamp, submitted version and approval or rejection outcome in the canonical task journal in the main Spamtroll repository.

Posting a forum announcement is a separate task and is not a substitute for catalogue submission. No forum or support message was sent as part of this preparation.
