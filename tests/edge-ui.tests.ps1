$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$contentPath = Join-Path $projectRoot "edge-extension\content.js"
$manifestPath = Join-Path $projectRoot "edge-extension\manifest.json"
$content = Get-Content -LiteralPath $contentPath -Raw
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$requiredPatterns = @(
    '.bar { width:max-content; max-width:calc(100vw - 16px); min-height:34px',
    'border:1px solid #344158',
    'border-radius:11px',
    'background:#151d2b',
    'button.primary',
    'background:#526fe7',
    'translateButton.className = "primary"',
    'button.close',
    'background:#263143',
    'button:focus-visible',
    'button.close { width:36px; min-width:36px',
    'svg { width:12px; height:12px',
    'const cardWidth = Math.min(400, Math.max(280',
    'Math.round((rect.width || 0) * 0.75)',
    '.card { width:100%; overflow:hidden; border-radius:11px',
    'font-size:14px; line-height:1.5',
    'max-height:180px; overflow:auto',
    '.action { min-height:32px',
    'if (!isAssistantEvent(event)) inspectSelection();'
)

foreach ($pattern in $requiredPatterns) {
    if ($content.IndexOf($pattern, [StringComparison]::Ordinal) -lt 0) {
        throw "Approved toolbar design token is missing: $pattern"
    }
}

$labels = @('"朗读"', '"中↔英 翻译"', '"语速：慢速"', '"语速：正常"', '"语速：快速"')
foreach ($label in $labels) {
    if ($content.IndexOf($label, [StringComparison]::Ordinal) -lt 0) {
        throw "Toolbar label changed or is missing: $label"
    }
}

if ($manifest.version -ne "1.7.3") {
    throw "Expected Edge extension version 1.7.3, got $($manifest.version)."
}

Write-Host "PASS: Edge toolbar matches the approved design tokens and keeps all labels." -ForegroundColor Green
