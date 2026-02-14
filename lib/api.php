<?php
/**
 * Spamtroll API Client
 *
 * NOTE: This class is currently not used by the admin panel (which uses
 * SpamtrollConfig::testConnection() directly). Kept for future use.
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
        $this->baseUrl = $baseUrl ?? preg_replace('#/[^/]+$#', '', $config['api_url']);
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
            'ip_address' => $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1',
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

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $this->timeout,
            CURLOPT_HTTPHEADER => [
                'X-API-Key: ' . $this->apiKey,
                'Content-Type: application/json',
                'User-Agent: Spamtroll-DirectAdmin/1.0',
            ],
        ]);

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
                'error' => 'Connection failed: ' . $curlError,
            ];
        }

        $decoded = json_decode($response, true);

        return [
            'success' => $httpCode >= 200 && $httpCode < 300,
            'code' => $httpCode,
            'data' => $decoded,
            'raw' => $response,
        ];
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
