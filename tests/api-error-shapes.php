<?php
/**
 * Checks SpamtrollAPI::normalizeError() against the four error bodies
 * the Spamtroll API can actually return. Shapes C and D put the boolean
 * `true` in `error`, which the old code concatenated into the panel's
 * message as "Test failed: 1".
 *
 *   php tests/api-error-shapes.php
 */

require_once __DIR__ . '/../lib/api.php';

$normalize = (new ReflectionClass('SpamtrollAPI'))->getMethod('normalizeError');
$normalize->setAccessible(true);

$pass = 0;
$fail = 0;

function check(string $label, $actual, $expected): void
{
    global $pass, $fail;
    if ($actual === $expected) {
        $pass++;
        printf("  ok   %s\n", $label);
        return;
    }
    $fail++;
    printf("  FAIL %s\n       expected %s\n       got      %s\n", $label, var_export($expected, true), var_export($actual, true));
}

function run(ReflectionMethod $m, string $json, int $code): array
{
    $decoded = json_decode($json, true);
    return $m->invoke(null, is_array($decoded) ? $decoded : [], $code);
}

// A — standard envelope
$r = run($normalize, '{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Content is required","request_id":"abc"}}', 422);
check('A: message extracted', $r['error'], 'Content is required');
check('A: application code extracted', $r['error_code'], 'VALIDATION_ERROR');

// B — 402 with usage
$r = run($normalize, '{"success":false,"error":{"code":"QUOTA_EXCEEDED","message":"Daily scan limit reached.","usage":{"current":200,"limit":200,"plan":"free","reset_at":"2026-08-24T00:00:00Z"}}}', 402);
check('B: message extracted', $r['error'], 'Daily scan limit reached.');
check('B: code extracted', $r['error_code'], 'QUOTA_EXCEEDED');
check('B: usage is no longer discarded', $r['usage']['plan'] ?? null, 'free');
check('B: usage limit', $r['usage']['limit'] ?? null, 200);

// C — rate limiter: `error` is boolean true, no `code`
$r = run($normalize, '{"error":true,"message":"Rate limit exceeded. Maximum 100 requests per minute."}', 429);
check('C: limiter message, not "1"', $r['error'], 'Rate limit exceeded. Maximum 100 requests per minute.');
check('C: no application code', $r['error_code'], null);

// D — Fiber's error handler
$r = run($normalize, '{"error":true,"message":"Cannot POST /api/v1/scan/chek"}', 404);
check('D: Fiber message, not "1"', $r['error'], 'Cannot POST /api/v1/scan/chek');

// Bodies that tell us nothing fall back to the status code
check('empty body on 401', run($normalize, '', 401)['error'], 'API key not recognised (401).');
check('HTML body on 502', run($normalize, '<html>bad gateway</html>', 502)['error'], 'Spamtroll API error (HTTP 502).');
check('403 is distinguished from 401', run($normalize, '{}', 403)['error'], 'Access refused (403) — the account is blocked or the platform is disabled.');
check('402 without a body still names the quota', run($normalize, '{}', 402)['error'], 'Daily scan quota exhausted (402). Upgrade the plan at spamtroll.io/dashboard/billing.');

printf("\npassed: %d  failed: %d\n", $pass, $fail);
exit($fail === 0 ? 0 : 1);
