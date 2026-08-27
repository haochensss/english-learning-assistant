$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $projectRoot "windows-helper\EnglishLearningAssistant.cs") -Raw
$setup = Get-Content -LiteralPath (Join-Path $projectRoot "配置腾讯云翻译.ps1") -Raw

$sourcePatterns = @(
    'internal static class TencentCloudTranslator',
    'ProtectedData.Unprotect',
    'DataProtectionScope.CurrentUser',
    'private const string Host = "tmt.tencentcloudapi.com";',
    'private const string Action = "TextTranslate";',
    'TC3-HMAC-SHA256',
    'TencentCloudTranslator.Translate(source)',
    'provider = "tencent";',
    'provider = "codex";'
)
foreach ($pattern in $sourcePatterns) {
    if (-not $source.Contains($pattern)) { throw "FAIL: missing Tencent safeguard: $pattern" }
}

$methodStart = $source.IndexOf('private static TranslationResult TranslateUncached',
    [StringComparison]::Ordinal)
$tencentCall = $source.IndexOf('TencentCloudTranslator.Translate(source)', $methodStart,
    [StringComparison]::Ordinal)
$codexCall = $source.IndexOf('string codexPath = ResolveCodexPath();', $methodStart,
    [StringComparison]::Ordinal)
if ($methodStart -lt 0 -or $tencentCall -lt $methodStart -or $codexCall -lt $methodStart -or
    $tencentCall -gt $codexCall) {
    throw "FAIL: Tencent translation must be attempted before Codex fallback."
}
if (-not $setup.Contains('[Security.Cryptography.ProtectedData]::Protect')) {
    throw "FAIL: setup script does not encrypt Tencent credentials with DPAPI."
}
if ($setup -match 'Write-Host[^\r\n]*(SecretId|SecretKey)\s*\$') {
    throw "FAIL: setup script may print a credential value."
}

Write-Host "PASS: Tencent TMT precedes Codex fallback and credentials are protected with user-scoped DPAPI."
