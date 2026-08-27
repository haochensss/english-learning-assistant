$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class ClipboardSequenceForSelectionTest {
    [DllImport("user32.dll")]
    public static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(System.IntPtr window);
}
'@

$projectRoot = Split-Path -Parent $PSScriptRoot
$binaryPath = Join-Path $projectRoot "dist\EnglishLearningAssistant.exe"
$assembly = [Reflection.Assembly]::LoadFrom($binaryPath)
$watcherType = $assembly.GetType("EnglishLearningAssistant.GlobalSelectionWatcher", $true)
$bindingFlags = [Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Static
$method = $watcherType.GetMethod("TryGetSelection", $bindingFlags)
if (-not $method) {
    throw "Could not locate the read-only selection method."
}

$childScript = @'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
$app = New-Object Windows.Application
$window = New-Object Windows.Window
$window.Title = "English Learning Assistant Selection Test"
$window.Width = 560
$window.Height = 160
$window.WindowStartupLocation = "CenterScreen"
$textBox = New-Object Windows.Controls.TextBox
$textBox.Text = "clipboard-safe UI Automation selection"
$textBox.FontSize = 20
$window.Content = $textBox
$window.Add_ContentRendered({
    $window.Activate() | Out-Null
    $textBox.Focus() | Out-Null
    $textBox.Select(0, 14)
})
$selectionTimer = New-Object Windows.Threading.DispatcherTimer
$selectionTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$selectionTimer.Add_Tick({
    $window.Activate() | Out-Null
    $textBox.Focus() | Out-Null
    $textBox.Select(0, 14)
})
$selectionTimer.Start()
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(15)
$timer.Add_Tick({ $timer.Stop(); $selectionTimer.Stop(); $window.Close() })
$timer.Start()
$app.Run($window) | Out-Null
'@
$encodedChild = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
$child = Start-Process powershell.exe -ArgumentList @(
    "-NoProfile", "-STA", "-EncodedCommand", $encodedChild
) -WindowStyle Hidden -PassThru

try {
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        $child.Refresh()
        if ($child.MainWindowTitle -eq "English Learning Assistant Selection Test") {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) {
        throw "Selection test window did not become ready."
    }
    [ClipboardSequenceForSelectionTest]::SetForegroundWindow($child.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 300

    $before = [ClipboardSequenceForSelectionTest]::GetClipboardSequenceNumber()
    $selectedText = ""
    for ($i = 0; $i -lt 20 -and $selectedText -ne "clipboard-safe"; $i++) {
        [ClipboardSequenceForSelectionTest]::SetForegroundWindow($child.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 100
        [object[]]$arguments = @(
            [Drawing.Rectangle]::FromLTRB(20, 20, 140, 40),
            [Drawing.Rectangle]::Empty
        )
        $selectedText = [string]$method.Invoke($null, $arguments)
    }
    $after = [ClipboardSequenceForSelectionTest]::GetClipboardSequenceNumber()

    if ($selectedText -ne "clipboard-safe") {
        throw "Read-only UI Automation selection failed. Actual: '$selectedText'"
    }
    if ($before -ne $after) {
        throw "Clipboard changed during selection capture: $before -> $after"
    }

    Write-Host "PASS: UI Automation read the selection without changing the clipboard." -ForegroundColor Green
}
finally {
    if (-not $child.HasExited) {
        $child.CloseMainWindow() | Out-Null
        if (-not $child.WaitForExit(2000)) {
            Stop-Process -Id $child.Id -Force
        }
    }
}
