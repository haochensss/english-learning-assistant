$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot "windows-helper\CodexSelectionReader.cs"
$source = Get-Content -LiteralPath $sourcePath -Raw

$watcherStart = $source.IndexOf("internal sealed class GlobalSelectionWatcher", [StringComparison]::Ordinal)
$watcherEnd = $source.IndexOf("internal static class NativeMethods", [StringComparison]::Ordinal)
if ($watcherStart -lt 0 -or $watcherEnd -le $watcherStart) {
    throw "无法定位 GlobalSelectionWatcher，剪贴板安全检查无法运行。"
}

$watcherSource = $source.Substring($watcherStart, $watcherEnd - $watcherStart)
$forbiddenPatterns = @(
    "Clipboard.",
    "SendKeys",
    "GetClipboardSequenceNumber",
    "TryCopySelection",
    "^c"
)

foreach ($pattern in $forbiddenPatterns) {
    if ($watcherSource.IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "后台选区监听器仍包含禁止的剪贴板操作：$pattern"
    }
}

$requiredPatterns = @(
    "_gestureStartedInCodex = ForegroundIsCodex()",
    "gestureStartedInCodex &&",
    "AutomationElement.IsTextPatternAvailableProperty",
    "TryReadSelection"
)

foreach ($pattern in $requiredPatterns) {
    if ($watcherSource.IndexOf($pattern, [StringComparison]::Ordinal) -lt 0) {
        throw "缺少截图误判防护或只读选区识别逻辑：$pattern"
    }
}

$intentionalClipboardWrites = [regex]::Matches($source, "Clipboard\.SetText\(").Count
if ($intentionalClipboardWrites -ne 1 -or
    $source.IndexOf('copy.Click += (s, e) => { Clipboard.SetText(_translation)',
        [StringComparison]::Ordinal) -lt 0) {
    throw "剪贴板写入必须仅保留在用户主动点击译文复制按钮的路径中。"
}

Write-Host "PASS: 后台选区识别不访问剪贴板，且截图手势必须从 Codex 窗口开始。" -ForegroundColor Green
