$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDirectory = Join-Path $projectRoot "dist"
$configPath = Join-Path $configDirectory "tencent-translation.json"
$entropy = [Text.Encoding]::UTF8.GetBytes("EnglishLearningAssistant.TencentTMT.v1")

function Protect-Secret([Security.SecureString]$secureValue) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
        $plainText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $clearBytes = [Text.Encoding]::UTF8.GetBytes($plainText)
        try {
            $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
                $clearBytes,
                $entropy,
                [Security.Cryptography.DataProtectionScope]::CurrentUser
            )
            return [Convert]::ToBase64String($protectedBytes)
        }
        finally {
            [Array]::Clear($clearBytes, 0, $clearBytes.Length)
        }
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

Write-Host "腾讯云机器翻译本机安全配置" -ForegroundColor Cyan
Write-Host "密钥只会以 Windows 当前用户 DPAPI 加密形式保存在本机。"
Write-Host "请勿把 SecretId 或 SecretKey 发到聊天、截图或 GitHub。"
Write-Host ""

$secretId = Read-Host "请输入腾讯云 SecretId" -AsSecureString
$secretKey = Read-Host "请输入腾讯云 SecretKey" -AsSecureString
$region = Read-Host "地域（直接回车使用 ap-beijing）"
if ([string]::IsNullOrWhiteSpace($region)) { $region = "ap-beijing" }

New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
$configuration = [ordered]@{
    version = 1
    provider = "tencent-tmt"
    region = $region.Trim()
    secretIdProtected = Protect-Secret $secretId
    secretKeyProtected = Protect-Secret $secretKey
}
$configuration | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM

# dist 已被 .gitignore 排除；密钥内容仍由 Windows 当前用户 DPAPI 加密。

$exePath = Join-Path $projectRoot "dist\EnglishLearningAssistant.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "尚未安装英语学习助手，请先运行安装英语学习助手.cmd。"
}
Get-CimInstance Win32_Process |
    Where-Object { $_.ExecutablePath -eq $exePath } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Start-Process -FilePath $exePath -WorkingDirectory (Split-Path -Parent $exePath) -WindowStyle Hidden

$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 200
    if (Get-NetTCPConnection -LocalPort 43128 -State Listen -ErrorAction SilentlyContinue) {
        $ready = $true
        break
    }
}
if (-not $ready) { throw "英语学习助手重新启动失败。" }

$headers = @{
    "X-English-Learning-Assistant-Token" = "8a6f67fb36e94a9f84a25d874906f1d4e60b9c4ae36246d8b4d7a2192e77c685"
}
$body = @{ type = "testTencent"; text = "Hello." } | ConvertTo-Json -Compress
try {
    $result = Invoke-RestMethod -Uri "http://127.0.0.1:43128/action" -Method Post `
        -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body
    if (-not $result.success -or $result.provider -ne "tencent") {
        throw "腾讯云没有返回有效译文。"
    }
    Write-Host ""
    Write-Host "腾讯云翻译配置成功，真实调用已通过：Hello. → $($result.result)" -ForegroundColor Green
    Write-Host "现在将优先使用腾讯云；额度耗尽或服务不可用时自动回退 Codex。"
}
catch {
    $detail = $_.ErrorDetails.Message
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
    throw "腾讯云真实调用验证失败：$detail"
}
