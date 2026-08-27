$ErrorActionPreference = "Stop"

Get-Process -Name "EnglishLearningAssistant" -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "EnglishLearningAssistant" -ErrorAction SilentlyContinue
$startupPath = [Environment]::GetFolderPath("Startup")
Remove-Item -LiteralPath (Join-Path $startupPath "英语学习助手.lnk") -Force -ErrorAction SilentlyContinue
$desktopPath = [Environment]::GetFolderPath("Desktop")
Remove-Item -LiteralPath (Join-Path $desktopPath "英语学习助手.lnk") -Force -ErrorAction SilentlyContinue

try {
    $taskService = New-Object -ComObject "Schedule.Service"
    $taskService.Connect()
    $taskService.GetFolder("\").DeleteTask("英语学习助手", 0)
}
catch {
    # 未创建任务时无需处理。
}

Write-Host "英语学习助手已经停止，并已移除启动入口和旧开机启动项。"
Write-Host "如需彻底移除，请在 Edge 扩展页面删除“英语学习助手”。"
