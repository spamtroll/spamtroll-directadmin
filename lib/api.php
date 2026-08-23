<?php
/**
 * Spamtroll API Client
 *
 * Used by the admin panel for email testing and account usage checks.
 */

require_once __DIR__ . '/config.php';

class SpamtrollAPI
{
    private $apiKey;
    private $baseUrl;
    private $timeout;

    /**
     * Create a new API client
     *
     * @param string|null $apiKey API key (loads from config if null)
     * @param string|null $baseUrl Base URL (loads from config if null)
     */
    public function __construct(?string $apiKey = null, ?string $baseUrl = null)
    {
        $config = SpamtrollConfig::load();

        $this->apiKey = $apiKey ?? $config['api_key'];
        // $config['api_url'] is already a base URL (…/api/v1). Earlier
        // versions of this class stripped the last path segment here to
        // accept both "…/api/v1" and "…/api/v1/scan/check" inputs, but
        // once api_url was pinned to the base, that strip turned
        // /api/v1 into /api — giving 404s on every request.
        $this->baseUrl = $baseUrl ?? $config['api_url'];
        $this->timeout = $config['timeout'] ?? 10;
    }

    /**
     * Test the API connection
     *
     * @return array Result with 'success' boolean
     */
    public function testConnection(): array
    {
        return $this->request('GET', '/scan/status');
    }

    /**
     * Get account usage/stats from API
     *
     * @return array Result with usage data
     */
    public function getAccountUsage(): array
    {
        return $this->request('GET', '/account/usage');
    }

    /**
     * Check a sample text for spam (for testing)
     *
     * @param string $content Content to check
     * @param string $source Source type (email, forum, etc.)
     * @return array Result with spam check data
     */
    public function checkSpam(string $content, string $source = 'email'): array
    {
        return $this->request('POST', '/scan/check', [
            'content' => $content,
            'source' => $source,
            'ip_address' => getenv('REMOTE_ADDR') ?: '127.0.0.1',
        ]);
    }

    /**
     * Make an API request
     *
     * @param string $method HTTP method (GET, POST)
     * @param string $endpoint API endpoint
     * @param array|null $data Request data for POST
     * @return array Result with 'success', 'code', 'data'
     */
    private function request(string $method, string $endpoint, ?array $data = null): array
    {
        if (empty($this->apiKey)) {
            return [
                'success' => false,
                'error' => 'API key not configured',
            ];
        }

        $url = rtrim($this->baseUrl, '/') . $endpoint;

        $responseHeaders = [];

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $this->timeout,
            // Without a connect timeout the whole budget can be spent on
            // a TCP handshake that never completes.
            CURLOPT_CONNECTTIMEOUT => 3,
            // Verification is on by default; stated explicitly so that
            // turning it off becomes a visible edit rather than an
            // accidental omission. Redirects stay off so the API key
            // header cannot be replayed to another host.
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_HTTPHEADER => [
                'X-API-Key: ' . $this->apiKey,
                'Content-Type: application/json',
                'User-Agent: Spamtroll-DirectAdmin/1.0',
            ],
            CURLOPT_HEADERFUNCTION => function ($ch, $header) use (&$responseHeaders) {
                $parts = explode(':', $header, 2);
                if (count($parts) === 2) {
                    $responseHeaders[strtolower(trim($parts[0]))] = trim($parts[1]);
                }
                return strlen($header);
            },
        ]);

        // CURLOPT_PROTOCOLS is deprecated from curl 7.85 / PHP 8.2.
        if (defined('CURLOPT_PROTOCOLS_STR')) {
            curl_setopt($ch, CURLOPT_PROTOCOLS_STR, 'https');
        } elseif (defined('CURLPROTO_HTTPS')) {
            curl_setopt($ch, CURLOPT_PROTOCOLS, CURLPROTO_HTTPS);
        }

        if ($method === 'POST' && $data !== null) {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        }

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        curl_close($ch);

        if (!empty($curlError)) {
            return [
                'success' => false,
                'code' => 0,
                'data' => null,
                'error' => 'Connection failed: ' . $curlError,
                'error_code' => null,
                'usage' => null,
                'retry_after' => null,
                'raw' => null,
            ];
        }

        $decoded = json_decode((string)$response, true);
        if (!is_array($decoded)) {
            $decoded = [];
        }

        // Backend envelopes successful replies as
        //   {"success": true, "data": {...actual payload...}}
        // Unwrap `data` for callers so they don't need to reach through
        // two levels and end up with status=unknown / score=N/A when
        // the envelope changes.
        $ok = $httpCode >= 200 && $httpCode < 300 && ($decoded['success'] ?? true);
        $payload = array_key_exists('data', $decoded) ? $decoded['data'] : $decoded;

        $failure = $ok
            ? ['error' => null, 'error_code' => null, 'usage' => null]
            : self::normalizeError($decoded, $httpCode);

        return [
            'success' => $ok,
            'code' => $httpCode,
            'data' => $payload,
            'error' => $failure['error'],
            'error_code' => $failure['error_code'],
            'usage' => $failure['usage'],
            'retry_after' => $responseHeaders['retry-after'] ?? null,
            'raw' => $response,
        ];
    }

    /**
     * Reduce the four different error bodies the API can return to one
     * shape: message, application code, quota usage.
     *
     *   A  {"success":false,"error":{"code":"...","message":"..."}}
     *   B  the same plus error.usage, on 402
     *   C  {"error":true,"message":"..."}        rate limiter
     *   D  {"error":true,"message":"Cannot POST /api/v1/..."}  Fiber
     *
     * C and D are the reason this exists: `error` there is the boolean
     * `true`, and reading it as the message produced "Test failed: 1"
     * in the admin panel.
     *
     * @param array $decoded Decoded response body ([] when unparseable)
     * @param int $httpCode HTTP status code
     * @return array{error: string, error_code: string|null, usage: array|null}
     */
    private static function normalizeError(array $decoded, int $httpCode): array
    {
        $error = null;
        $errorCode = null;
        $usage = null;

        if (isset($decoded['error']) && is_array($decoded['error'])) {
            $errorCode = $decoded['error']['code'] ?? null;
            $error = $decoded['error']['message'] ?? null;
            $usage = $decoded['error']['usage'] ?? null;
        } elseif (isset($decoded['message']) && is_string($decoded['message'])) {
            $error = $decoded['message'];
        } elseif (isset($decoded['error']) && is_string($decoded['error'])) {
            $error = $decoded['error'];
        }

        if (!is_string($error) || $error === '') {
            $error = self::describeStatus($httpCode);
        }

        return [
            'error' => $error,
            'error_code' => is_string($errorCode) ? $errorCode : null,
            'usage' => is_array($usage) ? $usage : null,
        ];
    }

    /**
     * Fallback message for a failing status code whose body told us
     * nothing useful (empty body, HTML from a proxy, truncated JSON).
     *
     * @param int $httpCode HTTP status code
     * @return string Human-readable message
     */
    private static function describeStatus(int $httpCode): string
    {
        switch ($httpCode) {
            case 400:
                return 'The API rejected the request (400). Check the API key is not being sent in the URL.';
            case 401:
                return 'API key not recognised (401).';
            case 402:
                return 'Daily scan quota exhausted (402). Upgrade the plan at spamtroll.io/dashboard/billing.';
            case 403:
                return 'Access refused (403) — the account is blocked or the platform is disabled.';
            case 404:
                return 'Endpoint not found (404).';
            case 422:
                return 'The API rejected the request payload (422).';
            case 429:
                return 'Rate limited (429) — too many requests for this API key.';
            default:
                if ($httpCode >= 500) {
                    return "Spamtroll API error (HTTP {$httpCode}).";
                }
                return "Unexpected response from the API (HTTP {$httpCode}).";
        }
    }

    /**
     * Get the base URL
     *
     * @return string Base URL
     */
    public function getBaseUrl(): string
    {
        return $this->baseUrl;
    }

    /**
     * Check if API key is configured
     *
     * @return bool True if API key is set
     */
    public function isConfigured(): bool
    {
        return !empty($this->apiKey);
    }
}
