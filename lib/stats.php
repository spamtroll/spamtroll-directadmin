<?php
/**
 * Spamtroll Statistics
 *
 * Parses Spamtroll logs to generate statistics for the dashboard.
 */

require_once __DIR__ . '/config.php';

class SpamtrollStats
{
    private $logFile;
    private $cacheFile;
    private $cacheTtl = 300; // 5 minutes cache

    /**
     * Create a new stats instance
     */
    public function __construct()
    {
        $this->logFile = SpamtrollConfig::getLogFile();
        $this->cacheFile = '/usr/local/directadmin/plugins/spamtroll/data/cache/stats.json';
    }

    /**
     * Get all statistics
     *
     * @param bool $useCache Whether to use cached data
     * @return array Statistics data
     */
    public function getStats(bool $useCache = true): array
    {
        // Try cache first
        if ($useCache) {
            $cached = $this->loadCache();
            if ($cached !== null) {
                return $cached;
            }
        }

        // Parse log file
        $stats = $this->parseLogFile();

        // Save to cache
        $this->saveCache($stats);

        return $stats;
    }

    /**
     * Parse the log file to extract statistics
     *
     * @return array Parsed statistics
     */
    private function parseLogFile(): array
    {
        $stats = [
            'total' => 0,
            'blocked' => 0,
            'safe' => 0,
            'errors' => 0,
            'today' => [
                'total' => 0,
                'blocked' => 0,
                'safe' => 0,
            ],
            'last_24h' => [
                'total' => 0,
                'blocked' => 0,
                'safe' => 0,
            ],
            'by_hour' => [],
            'top_blocked_domains' => [],
            'last_entries' => [],
            'generated_at' => date('Y-m-d H:i:s'),
        ];

        if (!file_exists($this->logFile)) {
            return $stats;
        }

        // Read last 10000 lines of log
        $lines = $this->tailFile($this->logFile, 10000);

        $now = time();
        $today = date('Y-m-d');
        $oneDayAgo = $now - 86400;

        $blockedDomains = [];
        $hourlyStats = [];
        $lastEntries = [];

        foreach ($lines as $line) {
            // Parse log line: 2024-01-15 10:30:45 [info] from=user@example.com ip=1.2.3.4 status=blocked score=15.5
            if (!preg_match('/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \[(\w+)\] (.+)$/', $line, $matches)) {
                continue;
            }

            $timestamp = strtotime($matches[1]);
            $level = $matches[2];
            $message = $matches[3];

            // Skip debug messages for stats
            if ($level === 'debug') {
                continue;
            }

            // Parse message components
            $data = $this->parseLogMessage($message);
            if (empty($data['status'])) {
                continue;
            }

            $stats['total']++;
            $isBlocked = ($data['status'] === 'blocked');

            if ($isBlocked) {
                $stats['blocked']++;
            } else {
                $stats['safe']++;
            }

            // Today's stats
            if (date('Y-m-d', $timestamp) === $today) {
                $stats['today']['total']++;
                if ($isBlocked) {
                    $stats['today']['blocked']++;
                } else {
                    $stats['today']['safe']++;
                }
            }

            // Last 24 hours
            if ($timestamp >= $oneDayAgo) {
                $stats['last_24h']['total']++;
                if ($isBlocked) {
                    $stats['last_24h']['blocked']++;
                } else {
                    $stats['last_24h']['safe']++;
                }

                // Hourly breakdown
                $hour = date('H:00', $timestamp);
                if (!isset($hourlyStats[$hour])) {
                    $hourlyStats[$hour] = ['blocked' => 0, 'safe' => 0];
                }
                if ($isBlocked) {
                    $hourlyStats[$hour]['blocked']++;
                } else {
                    $hourlyStats[$hour]['safe']++;
                }
            }

            // Track blocked domains
            if ($isBlocked && !empty($data['from'])) {
                $domain = $this->extractDomain($data['from']);
                if ($domain) {
                    $blockedDomains[$domain] = ($blockedDomains[$domain] ?? 0) + 1;
                }
            }

            // Keep last 50 entries (newest)
            $lastEntries[] = [
                'timestamp' => $matches[1],
                'from' => $data['from'] ?? '',
                'ip' => $data['ip'] ?? '',
                'status' => $data['status'],
                'score' => $data['score'] ?? 0,
            ];
            if (count($lastEntries) > 50) {
                array_shift($lastEntries);
            }
        }

        // Sort and limit top blocked domains
        arsort($blockedDomains);
        $stats['top_blocked_domains'] = array_slice($blockedDomains, 0, 10, true);

        // Format hourly stats
        ksort($hourlyStats);
        $stats['by_hour'] = $hourlyStats;

        // Reverse last entries (newest first)
        $stats['last_entries'] = array_reverse($lastEntries);

        return $stats;
    }

    /**
     * Parse a log message into components
     *
     * @param string $message Log message
     * @return array Parsed components
     */
    private function parseLogMessage(string $message): array
    {
        $data = [];

        // Extract key=value pairs
        if (preg_match('/from=([^\s]+)/', $message, $m)) {
            $data['from'] = $m[1];
        }
        if (preg_match('/ip=([^\s]+)/', $message, $m)) {
            $data['ip'] = $m[1];
        }
        if (preg_match('/status=([^\s]+)/', $message, $m)) {
            $data['status'] = $m[1];
        }
        if (preg_match('/score=([^\s]+)/', $message, $m)) {
            $data['score'] = floatval($m[1]);
        }

        return $data;
    }

    /**
     * Extract domain from email address
     *
     * @param string $email Email address
     * @return string|null Domain or null
     */
    private function extractDomain(string $email): ?string
    {
        if (preg_match('/@([^@]+)$/', $email, $matches)) {
            return strtolower($matches[1]);
        }
        return null;
    }

    /**
     * Read last N lines from a file efficiently
     *
     * @param string $file File path
     * @param int $lines Number of lines
     * @return array Lines
     */
    private function tailFile(string $file, int $lines): array
    {
        $result = [];
        $handle = @fopen($file, 'r');
        if (!$handle) {
            return $result;
        }

        // Use a buffer to read from end
        $buffer = '';
        $chunk = 4096;
        fseek($handle, 0, SEEK_END);
        $pos = ftell($handle);

        while ($pos > 0 && count($result) < $lines) {
            $readSize = min($chunk, $pos);
            $pos -= $readSize;
            fseek($handle, $pos);
            $buffer = fread($handle, $readSize) . $buffer;

            $bufferLines = explode("\n", $buffer);
            $buffer = array_shift($bufferLines); // Keep incomplete line

            foreach (array_reverse($bufferLines) as $line) {
                if (trim($line) !== '') {
                    array_unshift($result, $line);
                    if (count($result) >= $lines) {
                        break;
                    }
                }
            }
        }

        fclose($handle);

        // Add remaining buffer if it's a complete line
        if ($pos === 0 && trim($buffer) !== '' && count($result) < $lines) {
            array_unshift($result, $buffer);
        }

        return array_slice($result, -$lines);
    }

    /**
     * Load stats from cache
     *
     * @return array|null Cached data or null if expired/missing
     */
    private function loadCache(): ?array
    {
        if (!file_exists($this->cacheFile)) {
            return null;
        }

        $stat = stat($this->cacheFile);
        if ($stat === false || (time() - $stat['mtime']) > $this->cacheTtl) {
            return null;
        }

        $content = @file_get_contents($this->cacheFile);
        if ($content === false) {
            return null;
        }

        $data = json_decode($content, true);
        return is_array($data) ? $data : null;
    }

    /**
     * Save stats to cache
     *
     * @param array $stats Stats data
     */
    private function saveCache(array $stats): void
    {
        $cacheDir = dirname($this->cacheFile);
        if (!is_dir($cacheDir)) {
            @mkdir($cacheDir, 0770, true);
        }
        @file_put_contents($this->cacheFile, json_encode($stats));
        @chmod($this->cacheFile, 0660);
    }

    /**
     * Clear the stats cache
     */
    public function clearCache(): void
    {
        if (file_exists($this->cacheFile)) {
            @unlink($this->cacheFile);
        }
    }

    /**
     * Get recent log entries
     *
     * @param int $count Number of entries
     * @return array Log entries
     */
    public function getRecentLogs(int $count = 100): array
    {
        if (!file_exists($this->logFile)) {
            return [];
        }

        $lines = $this->tailFile($this->logFile, $count);
        return array_reverse($lines);
    }
}
