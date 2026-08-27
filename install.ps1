$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath = Join-Path $projectRoot "windows-helper\CodexSelectionReader.cs"
$distPath = Join-Path $projectRoot "dist"
$exePath = Join-Path $distPath "EnglishLearningAssistant.exe"
$legacyExePath = Join-Path $distPath "CodexSelectionReader.exe"
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

# 更新时只关闭本项目的新旧助手，避免锁住目标文件和本机端口。
Get-CimInstance Win32_Process |
    Where-Object { $_.ExecutablePath -eq $exePath -or $_.ExecutablePath -eq $legacyExePath } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$compiler = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "未找到 Windows C# 编译器。"
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
    "/reference:System.Windows.Forms.dll",
    "/reference:System.Drawing.dll",
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

# 1.3.0 起 Edge 通过仅限本机的回环端口通信，不再依赖浏览器原生消息注册。
Remove-Item -LiteralPath "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.tom.codex_reader" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $distPath "com.tom.codex_reader.json") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $legacyExePath -Force -ErrorAction SilentlyContinue

# 清理旧版开机启动方式，改由 Windows 任务计划程序独立启动。
# 这样助手不会成为 Codex 的子进程，也不会在 Codex 关闭或重启时一起退出。
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty -Path $runKey -Name "CodexSelectionReader" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runKey -Name "EnglishLearningAssistant" -ErrorAction SilentlyContinue

$startupPath = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupPath "英语学习助手.lnk"
Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue

$taskName = "英语学习助手"
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$taskService = New-Object -ComObject "Schedule.Service"
$taskService.Connect()
$taskFolder = $taskService.GetFolder("\")
$taskDefinition = $taskService.NewTask(0)
$taskDefinition.RegistrationInfo.Description = "在用户登录后运行英语学习助手，并独立于 Codex 保持后台运行。"
$taskDefinition.Principal.UserId = $currentUser
$taskDefinition.Principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN
$taskDefinition.Principal.RunLevel = 0 # TASK_RUNLEVEL_LUA
$taskDefinition.Settings.Enabled = $true
$taskDefinition.Settings.StartWhenAvailable = $true
$taskDefinition.Settings.DisallowStartIfOnBatteries = $false
$taskDefinition.Settings.StopIfGoingOnBatteries = $false
$taskDefinition.Settings.ExecutionTimeLimit = "PT0S"
$taskDefinition.Settings.MultipleInstances = 2 # TASK_INSTANCES_IGNORE_NEW

$logonTrigger = $taskDefinition.Triggers.Create(9) # TASK_TRIGGER_LOGON
$logonTrigger.Id = "CurrentUserLogon"
$logonTrigger.UserId = $currentUser
$logonTrigger.Delay = "PT5S"

$startAction = $taskDefinition.Actions.Create(0) # TASK_ACTION_EXEC
$startAction.Id = "StartEnglishLearningAssistant"
$startAction.Path = $exePath
$startAction.WorkingDirectory = $distPath

$task = $taskFolder.RegisterTaskDefinition(
    $taskName,
    $taskDefinition,
    6, # TASK_CREATE_OR_UPDATE
    $currentUser,
    $null,
    3, # TASK_LOGON_INTERACTIVE_TOKEN
    $null
)
$task.Run($null) | Out-Null

Write-Host ""
Write-Host "英语学习助手已安装并启动。" -ForegroundColor Green
Write-Host "独立后台任务：$taskName"
Write-Host "Edge 扩展目录：$projectRoot\edge-extension"
Write-Host "扩展 ID：jcajelkafkjjiieijeoddeagaipepace"
Write-Host "如扩展已加载，请在 edge://extensions 点击一次“重新加载”。"
