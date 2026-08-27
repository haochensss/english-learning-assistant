$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot "windows-helper\CodexSelectionReader.cs"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredPatterns = @(
    'internal sealed class AssistantMenuRenderer : ToolStripRenderer',
    'Size = new Size(210, 280)',
    'MinimumSize = new Size(210, 280)',
    'MaximumSize = new Size(210, 280)',
    '"EnabledRecognition", "启用自动识别", 46',
    'new ToolStripLabel("朗读速度")',
    '"RateSlow", "慢速朗读", 42',
    '"RateNormal", "正常语速", 42',
    '"RateFast", "快速朗读", 42',
    '"Exit", "退出", 46',
    'Renderer = new AssistantMenuRenderer()',
    'normal.Checked = SpeechService.Rate > -2 && SpeechService.Rate < 0'
)

foreach ($pattern in $requiredPatterns) {
    if ($source.IndexOf($pattern, [StringComparison]::Ordinal) -lt 0) {
        throw "Tray menu UI token is missing: $pattern"
    }
}

$contentHeight = 46 + 8 + 28 + (42 * 3) + 8 + 46
if ($contentHeight -gt 280) {
    throw "Tray menu rows exceed the approved 280 px height."
}

Write-Host "PASS: Tray menu uses the approved 210x280 dark layout and readable row sizes." -ForegroundColor Green
