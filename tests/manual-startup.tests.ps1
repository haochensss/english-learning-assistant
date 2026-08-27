$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$installer = Get-Content -LiteralPath (Join-Path $projectRoot "install.ps1") -Raw
$configurer = Get-Content -LiteralPath (Join-Path $projectRoot "配置腾讯云翻译.ps1") -Raw

$requiredInstallerTokens = @(
    'DeleteTask("英语学习助手", 0)',
    '[Environment]::GetFolderPath("Desktop")',
    'CreateShortcut($desktopShortcutPath)',
    '$desktopShortcut.TargetPath = $exePath',
    '$desktopShortcut.IconLocation = "$exePath,0"',
    '"/win32icon:$iconPath"',
    'Start-Process -FilePath $exePath -WorkingDirectory $distPath -WindowStyle Hidden'
)
foreach ($token in $requiredInstallerTokens) {
    if ($installer.IndexOf($token, [StringComparison]::Ordinal) -lt 0) {
        throw "Manual startup token is missing: $token"
    }
}

foreach ($forbidden in @('Triggers.Create(9)', 'RegisterTaskDefinition(')) {
    if ($installer.IndexOf($forbidden, [StringComparison]::Ordinal) -ge 0) {
        throw "Automatic startup code remains in installer: $forbidden"
    }
}

if ($configurer.IndexOf('Start-Process -FilePath $exePath', [StringComparison]::Ordinal) -lt 0) {
    throw "Tencent configuration no longer has a direct manual-mode restart path."
}

Write-Host "PASS: Installer removes login startup and creates a desktop-only manual launcher." -ForegroundColor Green
