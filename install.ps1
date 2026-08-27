$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "windows-helper\EnglishLearningAssistant.cs"
$distPath = Join-Path $projectRoot "dist"
$exePath = Join-Path $distPath "EnglishLearningAssistant.exe"
$iconPath = Join-Path $projectRoot "assets\EnglishLearningAssistant.ico"
$voiceEnginePath = Join-Path $projectRoot "voice-engine"
$voicePythonPath = Join-Path $voiceEnginePath ".venv\Scripts\python.exe"
$voiceRequirementsPath = Join-Path $voiceEnginePath "requirements.txt"
$voiceModelPath = Join-Path $voiceEnginePath "models\en_US-ryan-high.onnx"

New-Item -ItemType Directory -Force -Path $distPath | Out-Null

# Git 仓库不保存不可移植的 Python 虚拟环境；首次安装时在本机创建。
if (-not (Test-Path -LiteralPath $voicePythonPath)) {
    $pythonLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonLauncher) {
        & $pythonLauncher.Source -3 -m venv (Join-Path $voiceEnginePath ".venv")
    }
    elseif ($pythonCommand) {
        & $pythonCommand.Source -m venv (Join-Path $voiceEnginePath ".venv")
    }
    else {
        throw "未找到 Python 3.9 或更高版本，无法安装本地英文语音组件。"
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $voicePythonPath)) {
        throw "创建本地英文语音环境失败。"
    }
}

& $voicePythonPath -c "import piper" 2>$null
if ($LASTEXITCODE -ne 0) {
    & $voicePythonPath -m pip install --disable-pip-version-check --requirement $voiceRequirementsPath
    if ($LASTEXITCODE -ne 0) {
        throw "安装 Piper 本地英文语音组件失败。"
    }
}

if (-not (Test-Path -LiteralPath $voiceModelPath)) {
    throw "缺少 Ryan High 语音模型。使用 Git 克隆时请确认 Git LFS 已拉取模型文件。"
}

# 更新时只关闭本项目助手，避免锁住目标文件和本机端口。
Get-CimInstance Win32_Process |
    Where-Object { $_.ExecutablePath -eq $exePath } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$compiler = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "未找到 Windows C# 编译器。"
}
if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "缺少英语学习助手主题图标。"
}

function Find-SystemAssembly([string]$name) {
    $assembly = Get-ChildItem "C:\Windows\Microsoft.NET\assembly" -Filter $name -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $assembly) {
        throw "未找到系统组件：$name"
    }
    return $assembly
}

$speechAssembly = Find-SystemAssembly "System.Speech.dll"
$automationClientAssembly = Find-SystemAssembly "UIAutomationClient.dll"
$automationTypesAssembly = Find-SystemAssembly "UIAutomationTypes.dll"
$windowsBaseAssembly = Find-SystemAssembly "WindowsBase.dll"

$compilerArguments = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/out:$exePath",
    "/win32icon:$iconPath",
    "/reference:System.Windows.Forms.dll",
    "/reference:System.Drawing.dll",
    "/reference:System.Security.dll",
    "/reference:$speechAssembly",
    "/reference:$automationClientAssembly",
    "/reference:$automationTypesAssembly",
    "/reference:$windowsBaseAssembly",
    "/reference:System.Web.Extensions.dll",
    $sourcePath
)
& $compiler $compilerArguments

if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exePath)) {
    throw "本地助手编译失败。"
}

$codex = Get-Command codex.exe -ErrorAction Stop
Set-Content -LiteralPath (Join-Path $distPath "codex-path.txt") -Value $codex.Source -Encoding UTF8

# 清理所有旧版开机启动方式。助手改为只通过桌面快捷方式手动启动。
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty -Path $runKey -Name "EnglishLearningAssistant" -ErrorAction SilentlyContinue

$startupPath = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupPath "英语学习助手.lnk"
Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue

try {
    $taskService = New-Object -ComObject "Schedule.Service"
    $taskService.Connect()
    $taskService.GetFolder("\").DeleteTask("英语学习助手", 0)
}
catch {
    # 旧任务不存在时无需处理。
}

$desktopPath = [Environment]::GetFolderPath("Desktop")
$desktopShortcutPath = Join-Path $desktopPath "英语学习助手.lnk"
$shortcutShell = New-Object -ComObject WScript.Shell
$desktopShortcut = $shortcutShell.CreateShortcut($desktopShortcutPath)
$desktopShortcut.TargetPath = $exePath
$desktopShortcut.WorkingDirectory = $distPath
$desktopShortcut.IconLocation = "$exePath,0"
$desktopShortcut.Description = "手动开启英语学习助手"
$desktopShortcut.Save()

# 安装结束后启动一次；此后登录 Windows 不会自动启动。
Start-Process -FilePath $exePath -WorkingDirectory $distPath -WindowStyle Hidden

Write-Host ""
Write-Host "英语学习助手已安装并启动（手动模式）。" -ForegroundColor Green
Write-Host "桌面启动入口：$desktopShortcutPath"
Write-Host "已取消 Windows 登录自启；需要关闭时右键托盘图标并选择“退出”。"
Write-Host "Edge 扩展目录：$projectRoot\edge-extension"
Write-Host "扩展 ID：jcajelkafkjjiieijeoddeagaipepace"
Write-Host "如扩展已加载，请在 edge://extensions 点击一次“重新加载”。"
