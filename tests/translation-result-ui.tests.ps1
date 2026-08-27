$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot "windows-helper\CodexSelectionReader.cs"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredPatterns = @(
    'ClientSize = new Size(580, 250)',
    'FormBorderStyle = FormBorderStyle.None',
    'Text = "英语学习助手 · 翻译"',
    'Location = new Point(16, 56)',
    'Size = new Size(548, 118)',
    'MakeResultButton("朗读译文", 16, 190, 142',
    'MakeResultButton("复制译文", 168, 190, 142',
    'ScrollBars = RichTextBoxScrollBars.Vertical',
    'Font = new Font("Microsoft YaHei UI", 15.5f, FontStyle.Regular)',
    'Location = CalculateLocation(selectionBounds, ClientSize)',
    'selectionBounds.Bottom + gap',
    'Color.FromArgb(43, 43, 46)',
    'Color.FromArgb(102, 116, 232)'
)

foreach ($pattern in $requiredPatterns) {
    if ($source.IndexOf($pattern, [StringComparison]::Ordinal) -lt 0) {
        throw "Translation result UI token is missing: $pattern"
    }
}

$buttonBottom = 190 + 42
if ($buttonBottom -gt 250) {
    throw "Translation result buttons extend beyond the 250 px client area."
}

Write-Host "PASS: Translation result UI is 580x250 and all actions fit inside the client area." -ForegroundColor Green

$binaryPath = Join-Path $projectRoot "dist\EnglishLearningAssistant.exe"
if (Test-Path -LiteralPath $binaryPath) {
    $assembly = [Reflection.Assembly]::LoadFrom($binaryPath)
    $formType = $assembly.GetType("EnglishLearningAssistant.TranslationResultForm", $true)
    $flags = [Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Static
    $method = $formType.GetMethod("CalculateLocation", $flags)
    if (-not $method) { throw "Could not locate translation window positioning method." }

    $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $selection = [Drawing.Rectangle]::new($area.Left + 500, $area.Top + 100, 180, 28)
    $size = [Drawing.Size]::new(580, 250)
    $position = [Drawing.Point]$method.Invoke($null, [object[]]@($selection, $size))
    if ($position.Y -ne $selection.Bottom + 8) {
        throw "Translation window is not directly below the selection: $($position.Y)."
    }

    $bottomSelection = [Drawing.Rectangle]::new($area.Left + 500, $area.Bottom - 28, 180, 24)
    $fallback = [Drawing.Point]$method.Invoke($null, [object[]]@($bottomSelection, $size))
    if ($fallback.Y -ne $bottomSelection.Top - $size.Height - 8) {
        throw "Translation window does not move above a bottom-edge selection."
    }

    Write-Host "PASS: Translation window anchors 8 px below the selected text with an above-selection fallback." -ForegroundColor Green
}
