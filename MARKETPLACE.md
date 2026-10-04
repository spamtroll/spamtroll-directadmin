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

## Verified publication channels — 4 October 2026

The original task URL, `plugins.directadmin.com`, returned no A or AAAA addresses.
That result alone does not establish that DirectAdmin has no plugin directory.
Subsequent research requested by the user identified these official public paths:

| Channel | Verified purpose and limits |
| --- | --- |
| [DirectAdmin Popular Plugins](https://www.directadmin.com/extras-plugins.php) | Official list of selected plugins, linking to vendor websites and some downloadable packages. Its “Other plugins listed on the forum” link points to the forum below. No self-service plugin-submission form was found on this public page. |
| [3rd Party Software forum](https://forum.directadmin.com/forums/3rd-party-software.44/) | Active community area for third-party software and plugin release announcements. Posting requires an account. A [NodeJS plugin release from June 2026](https://forum.directadmin.com/threads/release-directadmin-nodejs-plugin.82360/) demonstrates this route, without establishing editorial admission rules for the official popular list. |
| [Historical 3rd Party Software Directory](https://forum.directadmin.com/threads/3rd-party-software-directory.19688/) | A community-maintained thread explicitly marked closed. It says the list is not affiliated with JBMC Software; do not treat it as a current submission queue. |
| [DirectAdmin Contacts](https://www.directadmin.com/contacts.php) | Official contact page with a message form. A possible place to ask about inclusion in the popular list; it is not documented as a dedicated plugin-submission workflow. |

Distribution and discovery are separate. DirectAdmin's documented plugin structure
supports vendor-supplied archive/version URLs, while the official list links out
to vendors. The existing Spamtroll download is a distribution endpoint, not proof
of admission to the official list. See the [plugin structure documentation](https://docs.directadmin.com/developer/plugins/structure.html).

**Inference:** the popular list appears editorially maintained rather than an open
upload catalogue, based on its fixed entries and the absence of a public submission
control on the reviewed page. Its actual admission procedure, reviewer contact and
acceptance rules still require confirmation; authenticated pages were not inspected.

## Submission record and remaining requirements

No listing request, contact form or forum message was sent; no approval was obtained.
The publication-path research is recorded in canonical Spamtroll task T-054. Actual
submission remains T-023; a forum announcement remains T-024. The current routes
above supersede the earlier assumption that the non-resolving historical hostname
was the only publication destination.

Before submission:

1. Confirm how DirectAdmin accepts requests for its official popular list, using the verified contact path if needed. Sending an inquiry requires a separate explicit message instruction. Do not assume the general contact form is a marketplace form.
2. Apply any catalogue-specific fields or screenshot requirements once they are known; do not claim compliance with unknown rules.
3. Decide and publish the release that includes the licensing/package fixes, then fetch its public archive and compare version, contents and checksums.
4. Obtain evidence on a supported DirectAdmin/Exim installation for the version submitted. Existing syntax, behavior and ACL simulation tests are useful but do not constitute a current installed-system certification.
5. Review this listing against the published package, pricing and confirmed admission fields, then request official inclusion through the confirmed route. A community announcement requires a forum account and a separate explicit posting instruction.
6. Record the submission URL/identifier, timestamp, submitted version and approval or rejection outcome in the canonical task journal in the main Spamtroll repository.

Posting a forum announcement makes the plugin discoverable through the route linked
by DirectAdmin, but does not establish inclusion in the official popular list. Record
each publication outcome separately and do not claim an official listing from a
community post alone.
