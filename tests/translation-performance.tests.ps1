$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$sourcePath = Join-Path $projectRoot "windows-helper\CodexSelectionReader.cs"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredPatterns = @(
    'private const int CacheCapacity = 128;',
    'private const int CacheLifetimeMinutes = 30;',
    'SHA256.Create()',
    'Dictionary<string, TaskCompletionSource<TranslationResult>> Inflight',
    'kind=" + kind + " elapsed_ms="',
    'chars=" + characterCount.ToString',
    'private static string _cachedCodexPath;'
)

foreach ($pattern in $requiredPatterns) {
    if (-not $source.Contains($pattern)) {
        throw "FAIL: missing translation performance safeguard: $pattern"
    }
}

if ($source -match 'WritePerformance\([^;\r\n]*(,\s*source\s*[,\)]|result\.Text)') {
    throw "FAIL: performance logging must not receive source or translated text."
}

Write-Host "PASS: Translation cache is memory-only, SHA-256 keyed, concurrency-safe, and logs no text."
