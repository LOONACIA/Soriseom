#Requires -Version 7
<#
.SYNOPSIS
    Deploys the current build as the dev package and checks the running app through UI Automation.

.DESCRIPTION
    Runs on the live desktop: windows appear and can take focus, and the dev package is registered again.
    Starts from default settings and restores the user's settings, startup state and do not disturb when it ends, including
    on the next run if this one dies.

    Saves the app's popup trace to app-trace.log in OutDir. A Release build has no trace, so only the script's own lines appear there.

    Only Claude runs this. Codex must not, see docs/ADR.md ADR-009.

    Exit codes: 0 all checks passed, 1 a check failed, 3 this desktop cannot run the checks right now
    (locked, full-screen, do not disturb, or other media playback holds the current session), which says nothing about the code.

.PARAMETER Scenario
    Comma-separated subset of: launch, relaunch, startup, language, media, popupsize, theme, dnd, tray, storeshots.
    storeshots captures the materials for the Store screenshots and is not included in the default list.

.PARAMETER Configuration
    Build configuration. Defaults to Debug; Release is the trimmed build users receive.
    The dev package remains registered with this build after the run ends.

.PARAMETER AfterSignIn
    Read-only check to run after a real sign-in: no build, no deploy, no launch.

.PARAMETER OutDir
    Where screenshots and app-trace.log go. Defaults to a new temp directory.

.EXAMPLE
    pwsh -NoProfile -File tools/smoke/Smoke.ps1 -Scenario language,media
#>
param(
    [string] $Scenario = 'launch,relaunch,startup,language,media,popupsize,theme,dnd,tray',
    [ValidateSet('Debug', 'Release')] [string] $Configuration = 'Debug',
    [switch] $AfterSignIn,
    [string] $OutDir
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class SmokeNative {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out RECT value, int size);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window, ref POINT point);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] public static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll")] public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint action, uint param, out RECT rect, uint winIni);
    [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
    [DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int state);
}

// Saves the app's PopupTrace lines beside the script's own marks. The app writes them through OutputDebugString.
public static class SmokeTrace {
    const string Prefix = "SoriseomTrace ";
    static readonly object Gate = new object();
    static StreamWriter writer;
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateEventW(IntPtr attributes, bool manualReset, bool initialState, string name);
    [DllImport("kernel32.dll")] static extern bool SetEvent(IntPtr handle);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateFileMappingW(IntPtr file, IntPtr attributes, uint protect, uint sizeHigh, uint sizeLow, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr MapViewOfFile(IntPtr mapping, uint access, uint offsetHigh, uint offsetLow, UIntPtr bytes);

    public static void Start(string path) {
        IntPtr ready = CreateEventW(IntPtr.Zero, false, false, "DBWIN_BUFFER_READY");
        IntPtr data = CreateEventW(IntPtr.Zero, false, false, "DBWIN_DATA_READY");
        IntPtr mapping = CreateFileMappingW(new IntPtr(-1), IntPtr.Zero, 4, 0, 4096, "DBWIN_BUFFER");
        IntPtr view = mapping == IntPtr.Zero ? IntPtr.Zero : MapViewOfFile(mapping, 4, 0, 0, new UIntPtr(4096));
        if (ready == IntPtr.Zero || data == IntPtr.Zero || view == IntPtr.Zero) {
            throw new System.ComponentModel.Win32Exception();
        }

        writer = new StreamWriter(path, false, new UTF8Encoding(false));
        var thread = new Thread(() => {
            while (true) {
                SetEvent(ready);
                if (WaitForSingleObject(data, 1000) != 0) continue;
                int pid = Marshal.ReadInt32(view);
                string message = Marshal.PtrToStringAnsi(view + 4);
                if (message != null && message.StartsWith(Prefix, StringComparison.Ordinal)) {
                    Append("app pid=" + pid + " " + message.Substring(Prefix.Length).TrimEnd());
                }
            }
        });
        thread.IsBackground = true;
        thread.Start();
    }

    public static void Mark(string text) {
        Append("smoke " + text);
    }

    static void Append(string text) {
        lock (Gate) {
            if (writer == null) return;
            writer.WriteLine(DateTime.Now.ToString("HH:mm:ss.fff") + " " + text);
            writer.Flush();
        }
    }
}
'@
# Per-monitor aware, so UI Automation, window rects and screenshots all use physical pixels.
[void][SmokeNative]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$AppProject = Join-Path $RepoRoot 'src\Soriseom.App'
# The layout Visual Studio deploys from. Reusing it keeps both tools on one registered location.
$AppxDir = Join-Path $AppProject 'bin\x64\Debug\net10.0-windows10.0.26100.0\win-x64\AppX'
$PackageName = ([xml](Get-Content (Join-Path $AppProject 'Package.appxmanifest'))).Package.Identity.Name
$ProcessName = 'Soriseom.App'
$StartupTaskId = 'SoriseomStartup'
$BackupDir = Join-Path ([IO.Path]::GetTempPath()) 'soriseom-smoke-backup'
$BackupFile = Join-Path $BackupDir 'backup.json'
# Packaged processes get AppData redirected, so the in-package helper answers through an ignored repo folder.
$ExchangeDir = Join-Path $AppProject 'bin\smoke-exchange'

# Windows Settings is registered on every install, so the media session gets a resolvable app name.
$FixtureAppId = 'windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'
# Store screenshots show this app's name in the list, and Edge's name is the same in every language.
$StoreFixtureAppId = 'MSEdge'
$FixtureArtist = 'SmokeArtist'
$FirstTrack = 'SmokeTrackA'
$SecondTrack = 'SmokeTrackB'

# StartupTaskState values as Windows stores them.
$StartupDisabled = 0
$StartupDisabledByUser = 1
$StartupEnabled = 2

# Windows Settings has the only way to change do not disturb: no public API sets it.
$DoNotDisturbSwitchId = 'SystemSettings_Notifications_QuietHours_MuteNotification_Enabled_ToggleSwitch'
# Exists only while this script holds do not disturb on, so the next run can undo it if this one dies.
$DoNotDisturbMarker = Join-Path $BackupDir 'do-not-disturb-on.txt'

$Ae = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]
$TogglePattern = [System.Windows.Automation.TogglePattern]::Pattern
$WindowPattern = [System.Windows.Automation.WindowPattern]::Pattern
$InvokePattern = [System.Windows.Automation.InvokePattern]::Pattern
$ExpandPattern = [System.Windows.Automation.ExpandCollapsePattern]::Pattern
$SelectionPattern = [System.Windows.Automation.SelectionPattern]::Pattern
$SelectionItemPattern = [System.Windows.Automation.SelectionItemPattern]::Pattern
$RangeValuePattern = [System.Windows.Automation.RangeValuePattern]::Pattern

$script:FailedChecks = 0
$script:UnavailableReason = $null

function Write-Line([string] $Text) {
    [Console]::Out.WriteLine($Text)
}

function Check([string] $Name, [bool] $Passed, [string] $Detail) {
    if ($Passed) {
        Write-Line "PASS $Name"
        return
    }

    $script:FailedChecks++
    Write-Line "FAIL $Name$(if ($Detail) { ": $Detail" })"
}

function Wait-For([scriptblock] $Condition, [int] $TimeoutMs = 8000) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
        # UI Automation elements can vanish while they are being read, which only means "not yet".
        try { $value = & $Condition } catch { $value = $null }
        if ($value) { return $value }
        Start-Sleep -Milliseconds 100
    } while ($watch.ElapsedMilliseconds -lt $TimeoutMs)
    return $null
}

function Test-FullScreen {
    $state = 0
    [void][SmokeNative]::SHQueryUserNotificationState([ref]$state)
    # Not present, busy, full-screen Direct3D, presentation mode: the app hides popups or cannot be driven.
    return $state -in 1, 2, 3, 4
}

function Get-UnavailableReason {
    $desktop = [SmokeNative]::OpenInputDesktop(0, $false, 0x0100)
    if ($desktop -eq [IntPtr]::Zero) { return 'the desktop is locked' }
    [void][SmokeNative]::CloseDesktop($desktop)

    if (Test-FullScreen) { return 'a full-screen app or screen saver is active' }
    return $null
}

function Set-PackagePaths([string] $FamilyName) {
    $script:FamilyName = $FamilyName
    $script:Aumid = "$FamilyName!App"
    $script:SettingsFile = Join-Path $env:LOCALAPPDATA "Packages\$FamilyName\Settings\settings.dat"
    $script:StartupKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$FamilyName\$StartupTaskId"
}

function Get-NotificationMode {
    $helper = Join-Path $PSScriptRoot 'NotificationMode.ps1'
    return (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper).Trim()
}

function Test-DoNotDisturbOn {
    return (Get-NotificationMode) -ne 'Unrestricted'
}

function Set-DoNotDisturb([bool] $On) {
    Start-Process 'ms-settings:notifications'
    # Not named $condition: variables are case-insensitive, and Wait-For has a parameter called $Condition.
    $byId = [System.Windows.Automation.PropertyCondition]::new($Ae::AutomationIdProperty, $DoNotDisturbSwitchId)
    $element = Wait-For { $Ae::RootElement.FindFirst($Scope::Descendants, $byId) } 20000
    if (-not $element) { throw 'the do not disturb switch was not found in Windows Settings' }

    $toggle = $element.GetCurrentPattern($TogglePattern)
    if (($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) -ne $On) { $toggle.Toggle() }
    Get-Process SystemSettings -ErrorAction SilentlyContinue | ForEach-Object { [void]$_.CloseMainWindow() }
    if (-not (Wait-For { (Test-DoNotDisturbOn) -eq $On })) { throw "do not disturb did not change to $On" }
}

function Get-StartupState {
    (Get-ItemProperty -Path $script:StartupKey -Name State -ErrorAction SilentlyContinue).State
}

function Set-StartupState([int] $State) {
    if (-not (Test-Path $script:StartupKey)) { [void](New-Item -Path $script:StartupKey -Force) }
    Set-ItemProperty -Path $script:StartupKey -Name State -Value $State -Type DWord
}

function Invoke-LanguageOverride([string] $Set) {
    [void](New-Item -ItemType Directory -Force -Path $ExchangeDir)
    $result = Join-Path $ExchangeDir 'override.txt'
    Remove-Item $result -Force -ErrorAction SilentlyContinue
    $setArgument = if ($PSBoundParameters.ContainsKey('Set')) { "-Set `"$Set`"" } else { '' }
    $helper = Join-Path $PSScriptRoot 'LanguageOverride.ps1'
    Invoke-CommandInDesktopPackage -PackageFamilyName $script:FamilyName -AppId App -Command 'powershell.exe' `
        -Args "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$helper`" -ResultPath `"$result`" $setArgument"
    if (-not (Wait-For { (Test-Path $result) -and (Get-Item $result).Length -gt 0 })) { throw 'the language override helper did not answer' }
    $answer = (Get-Content $result -Raw).Trim()
    Remove-Item $ExchangeDir -Recurse -Force
    if (-not $answer.StartsWith('=')) { throw "the language override helper failed: $answer" }
    return $answer.Substring(1)
}

# settings.dat is a registry hive, so its transaction logs (settings.dat.LOG1, .LOG2) travel with it.
function Remove-SettingsFiles {
    [void](Wait-For { Remove-Item "$($script:SettingsFile)*" -Force; $true })
}

function Save-UserState([string] $FamilyName) {
    Set-PackagePaths $FamilyName
    [void](New-Item -ItemType Directory -Force -Path $BackupDir)
    $hadSettings = Test-Path $script:SettingsFile
    if ($hadSettings) { Copy-Item "$($script:SettingsFile)*" $BackupDir -Force }
    @{
        familyName = $FamilyName
        hadSettings = $hadSettings
        startupState = Get-StartupState
        languageOverride = Invoke-LanguageOverride
    } | ConvertTo-Json | Set-Content $BackupFile -Encoding utf8
}

function Restore-UserState {
    $backup = Get-Content $BackupFile -Raw | ConvertFrom-Json
    Set-PackagePaths $backup.familyName
    if (-not (Get-AppxPackage -Name $PackageName)) {
        Write-Line "the package is not registered, so the backup stays in $BackupDir for the next run"
        return
    }

    Stop-App
    Remove-SettingsFiles
    if ($backup.hadSettings) { Copy-Item (Join-Path $BackupDir 'settings.dat*') (Split-Path $script:SettingsFile) -Force }
    [void](Invoke-LanguageOverride $backup.languageOverride)

    if ($null -ne $backup.startupState) {
        Set-StartupState $backup.startupState
    } else {
        # The task had never been armed. Leaving the key would start the dev build at every sign-in.
        Remove-Item $script:StartupKey -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $DoNotDisturbMarker) { Set-DoNotDisturb $false }
    Remove-Item $BackupDir -Recurse -Force
    Write-Line 'restored the settings and startup state from before this run'
}

function Build-Msix {
    # Remove old packages so skipped packaging cannot select a stale MSIX from another configuration.
    Remove-Item -LiteralPath (Join-Path $AppProject 'AppPackages') -Recurse -Force -ErrorAction SilentlyContinue
    $output = & dotnet build $AppProject -c $Configuration -p:Platform=x64 -p:GenerateAppxPackageOnBuild=true -p:AppxPackageSigningEnabled=false -p:AppxBundle=Never -v q 2>&1
    if ($LASTEXITCODE -ne 0) {
        $output | ForEach-Object { Write-Line "$_" }
        throw 'build failed'
    }

    (Get-ChildItem (Join-Path $AppProject 'AppPackages') -Recurse -Filter '*.msix' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Deploy-Package([string] $MsixPath) {
    $layout = Join-Path ([IO.Path]::GetTempPath()) "soriseom-smoke-layout-$PID"
    [IO.Compression.ZipFile]::ExtractToDirectory($MsixPath, $layout)
    # A CLI build does not refresh this folder, so the package contents are copied in.
    & robocopy $layout $AppxDir /E /PURGE /NFL /NDL /NJH /NJS /NP /XF AppxBlockMap.xml '[Content_Types].xml' AppxSignature.p7x | Out-Null
    $copyResult = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    Remove-Item $layout -Recurse -Force
    if ($copyResult -ge 8) { throw "robocopy failed with exit code $copyResult" }

    # Windows refuses to register a development package over itself (0x80073CFB).
    $existing = Get-AppxPackage -Name $PackageName
    if ($existing) { Remove-AppxPackage -Package $existing.PackageFullName -PreserveApplicationData }
    Add-AppxPackage -Register (Join-Path $AppxDir 'AppxManifest.xml')
}

function Get-AppProcess {
    @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
}

function Stop-App {
    Get-AppProcess | ForEach-Object { Stop-Process -Id $_.Id -Force }
    [void](Wait-For { (Get-AppProcess).Count -eq 0 })
    [SmokeTrace]::Mark('app stopped')
}

function Start-AppActivation {
    Start-Process "shell:AppsFolder\$script:Aumid"
}

function Find-Id($Root, [string] $Id) {
    $condition = [System.Windows.Automation.PropertyCondition]::new($Ae::AutomationIdProperty, $Id)
    $Root.FindFirst($Scope::Descendants, $condition)
}

# The settings window and the popup share a window class, so they are told apart by their content.
function Get-VisibleWindow([string] $ContentId) {
    foreach ($process in Get-AppProcess) {
        $condition = [System.Windows.Automation.PropertyCondition]::new($Ae::ProcessIdProperty, $process.Id)
        foreach ($window in $Ae::RootElement.FindAll($Scope::Children, $condition)) {
            if ([SmokeNative]::IsWindowVisible([IntPtr]$window.Current.NativeWindowHandle) -and (Find-Id $window $ContentId)) {
                return $window
            }
        }
    }
}

function Get-SettingsWindow { Get-VisibleWindow 'SettingsHeader' }

function Get-PopupWindow { Get-VisibleWindow 'TitleText' }

function Get-SettingsElement([string] $Id) {
    Find-Id (Get-SettingsWindow) $Id
}

function Open-Settings {
    if (-not (Get-SettingsWindow)) { Start-AppActivation }
    # A first launch after registering can take a while.
    if (-not (Wait-For { Get-SettingsWindow } 30000)) { throw 'the settings window did not open' }
    [void](Wait-For { (Get-AppProcess).Count -eq 1 })
    [SmokeTrace]::Mark('settings window open')
}

function Close-Settings {
    (Get-SettingsWindow).GetCurrentPattern($WindowPattern).Close()
    [void](Wait-For { -not (Get-SettingsWindow) })
}

function Restart-App {
    Stop-App
    Open-Settings
}

# Activating the window makes the app read the startup state again.
function Reopen-Settings {
    Close-Settings
    Open-Settings
}

function Get-Resource([string] $Culture, [string] $Name) {
    $resources = [xml](Get-Content (Join-Path $AppProject "Strings\$Culture\Resources.resw") -Encoding utf8)
    ($resources.root.data | Where-Object name -EQ $Name).value
}

# PrintWindow renders the window even when another window covers it.
# Settings windows carry an invisible resize border that it renders as black bands on three sides.
function Get-WindowBitmap($Window) {
    $handle = [IntPtr]$Window.Current.NativeWindowHandle
    $rect = [SmokeNative+RECT]::new()
    [void][SmokeNative]::GetWindowRect($handle, [ref]$rect)
    $bitmap = [System.Drawing.Bitmap]::new($rect.Right - $rect.Left, $rect.Bottom - $rect.Top)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    [void][SmokeNative]::PrintWindow($handle, $hdc, 2)
    $graphics.ReleaseHdc($hdc)
    $graphics.Dispose()
    return $bitmap
}

function Save-Screenshot($Window, [string] $Name) {
    $bitmap = Get-WindowBitmap $Window
    $path = Join-Path $OutDir "$Name.png"
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    Write-Line "screenshot $path"
}

# Tray icons have no window, and PrintWindow captures transparent popups as blank images, so copy from the screen.
function Save-ElementScreenshot($Element, [string] $Name) {
    $bounds = $Element.Current.BoundingRectangle
    $bitmap = [System.Drawing.Bitmap]::new([int]$bounds.Width, [int]$bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen([int]$bounds.X, [int]$bounds.Y, 0, 0, $bitmap.Size)
    $graphics.Dispose()
    $path = Join-Path $OutDir "$Name.png"
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    Write-Line "screenshot $path"
}

# GetWindowRect and UI Automation bounds include invisible resize borders; DWM returns the visible frame.
function Save-WindowFrameScreenshot($Window, [string] $Name) {
    $rect = [SmokeNative+RECT]::new()
    # DWMWA_EXTENDED_FRAME_BOUNDS
    $result = [SmokeNative]::DwmGetWindowAttribute([IntPtr]$Window.Current.NativeWindowHandle, 9, [ref]$rect, 16)
    if ($result -ne 0) { throw "DwmGetWindowAttribute failed: $result" }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $path = Join-Path $OutDir "$Name.png"
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    Write-Line "screenshot $path"
}

function Test-Launch {
    Stop-App
    Start-AppActivation
    Check 'a normal launch opens settings' ([bool](Wait-For { Get-SettingsWindow } 30000))
    Check 'a normal launch runs one process' ([bool](Wait-For { (Get-AppProcess).Count -eq 1 }))
    Save-Screenshot (Get-SettingsWindow) 'settings'
}

function Test-Relaunch {
    Open-Settings
    $processId = (Get-AppProcess)[0].Id
    Close-Settings
    Check 'closing settings hides the window and keeps the app running' (-not (Get-SettingsWindow) -and (Get-AppProcess).Count -eq 1)
    Start-AppActivation
    Check 'a second launch reopens settings' ([bool](Wait-For { Get-SettingsWindow }))
    Check 'a second launch hands over to the running process' ([bool](Wait-For { (Get-AppProcess).Count -eq 1 -and (Get-AppProcess)[0].Id -eq $processId }))
}

function Test-Startup {
    Open-Settings
    Set-StartupState $StartupEnabled
    Reopen-Settings
    $isOnAndEnabled = {
        $toggle = Get-SettingsElement 'LaunchAtStartupToggle'
        $toggle.Current.IsEnabled -and $toggle.GetCurrentPattern($TogglePattern).Current.ToggleState -eq 'On'
    }
    Check 'the switch shows an enabled startup task as on' ([bool](Wait-For $isOnAndEnabled))

    (Get-SettingsElement 'LaunchAtStartupToggle').GetCurrentPattern($TogglePattern).Toggle()
    Check 'turning the switch off disables the startup task' ([bool](Wait-For { (Get-StartupState) -eq $StartupDisabled })) "state is $(Get-StartupState)"
    (Get-SettingsElement 'LaunchAtStartupToggle').GetCurrentPattern($TogglePattern).Toggle()
    Check 'turning the switch on enables the startup task' ([bool](Wait-For { (Get-StartupState) -eq $StartupEnabled })) "state is $(Get-StartupState)"

    Set-StartupState $StartupDisabledByUser
    Reopen-Settings
    $isLockedOff = {
        $toggle = Get-SettingsElement 'LaunchAtStartupToggle'
        -not $toggle.Current.IsEnabled -and $toggle.GetCurrentPattern($TogglePattern).Current.ToggleState -eq 'Off'
    }
    Check 'a task disabled by the user locks the switch off' ([bool](Wait-For $isLockedOff))
    Check 'a task disabled by the user shows the notice' ([bool](Wait-For { Get-SettingsElement 'LaunchAtStartupNotice' }))
    Save-Screenshot (Get-SettingsWindow) 'startup-locked'

    Set-StartupState $StartupEnabled
    Reopen-Settings
    Check 'an enabled task unlocks the switch' ([bool](Wait-For $isOnAndEnabled))
    Check 'an enabled task hides the notice' ([bool](Wait-For { -not (Get-SettingsElement 'LaunchAtStartupNotice') }))
}

function Select-ComboBoxItem([string] $ComboBoxId, [string] $ItemId) {
    $combo = Get-SettingsElement $ComboBoxId
    $combo.GetCurrentPattern($ExpandPattern).Expand()
    $item = Wait-For { Find-Id $combo $ItemId }
    if (-not $item) { throw "combo box item $ItemId did not appear" }
    $item.GetCurrentPattern($SelectionItemPattern).Select()
    $isSelected = {
        $selection = (Get-SettingsElement $ComboBoxId).GetCurrentPattern($SelectionPattern).Current.GetSelection()
        $selection.Count -eq 1 -and $selection[0].Current.AutomationId -eq $ItemId
    }
    if (-not (Wait-For $isSelected)) { throw "combo box item $ItemId was not selected" }
    $isCollapsed = {
        $state = (Get-SettingsElement $ComboBoxId).GetCurrentPattern($ExpandPattern)
        if ($state.Current.ExpandCollapseState -ne 'Collapsed') { $state.Collapse() }
        $state.Current.ExpandCollapseState -eq 'Collapsed'
    }
    [void](Wait-For $isCollapsed)
}

function Test-Language {
    $systemIsKorean = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ko'
    $systemCulture = if ($systemIsKorean) { 'ko-KR' } else { 'en-US' }
    $otherCulture = if ($systemIsKorean) { 'en-US' } else { 'ko-KR' }
    $otherItem = if ($systemIsKorean) { 'LanguageEnglish' } else { 'LanguageKorean' }
    $header = { (Get-SettingsElement 'SettingsHeader').Current.Name }

    Open-Settings
    Check 'no restart notice before choosing a language' (-not (Get-SettingsElement 'LanguageRestartNotice'))
    Select-ComboBoxItem 'LanguageComboBox' $otherItem
    Check 'choosing another language shows the restart notice' ([bool](Wait-For { Get-SettingsElement 'LanguageRestartNotice' }))
    Save-Screenshot (Get-SettingsWindow) 'language-notice'
    Select-ComboBoxItem 'LanguageComboBox' 'LanguageSystem'
    Check 'choosing the launch language hides the restart notice' ([bool](Wait-For { -not (Get-SettingsElement 'LanguageRestartNotice') }))

    Select-ComboBoxItem 'LanguageComboBox' $otherItem
    Restart-App
    $expected = Get-Resource $otherCulture 'SettingsHeader.Text'
    Check 'the chosen language applies after a restart' ([bool](Wait-For { (& $header) -eq $expected })) "header is '$(& $header)'"
    Save-Screenshot (Get-SettingsWindow) 'language-applied'

    Select-ComboBoxItem 'LanguageComboBox' 'LanguageSystem'
    Restart-App
    $expected = Get-Resource $systemCulture 'SettingsHeader.Text'
    Check 'the system language returns after a restart' ([bool](Wait-For { (& $header) -eq $expected })) "header is '$(& $header)'"
}

# Follows one popup of a fixture track. Other titles are never read out: a real media session can show up here.
function Watch-Popup([string] $Title, [string] $ScreenshotName) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $seen = @{ Shown = $false; StolenFocus = $false; FullScreen = $false }
    $popup = $null
    while (-not $popup -and $watch.Elapsed.TotalSeconds -lt 12) {
        if (Test-FullScreen) { $seen.FullScreen = $true }
        $candidate = try { Get-PopupWindow } catch { $null }
        $current = try { if ($candidate) { (Find-Id $candidate 'TitleText').Current.Name } } catch { $null }
        if ($current -eq $Title) { $popup = $candidate } else { Start-Sleep -Milliseconds 40 }
    }

    if (-not $popup) {
        [SmokeTrace]::Mark("popup not seen $Title")
        return $seen
    }

    # From here on only Win32 state decides: a UI Automation read can fail for a moment while the window is up.
    $seen.Shown = $true
    [SmokeTrace]::Mark("popup seen $Title")
    $shownAt = $watch.Elapsed.TotalSeconds
    $handle = [IntPtr]$popup.Current.NativeWindowHandle
    $seen.ExStyle = [SmokeNative]::GetWindowLong($handle, -20)
    $screenshotTaken = -not $ScreenshotName
    while ([SmokeNative]::IsWindowVisible($handle) -and $watch.Elapsed.TotalSeconds - $shownAt -lt 12) {
        if (Test-FullScreen) { $seen.FullScreen = $true }
        if ([SmokeNative]::GetForegroundWindow() -eq $handle) { $seen.StolenFocus = $true }
        $bounds = [SmokeNative+RECT]::new()
        [void][SmokeNative]::GetWindowRect($handle, [ref]$bounds)
        $seen.Bounds = $bounds
        if (-not $screenshotTaken -and $watch.Elapsed.TotalSeconds - $shownAt -gt 1) {
            $current = try { (Find-Id $popup 'TitleText').Current.Name } catch { $null }
            if ($current -eq $Title) {
                Save-ElementScreenshot $popup $ScreenshotName
                $screenshotTaken = $true
            }
        }

        Start-Sleep -Milliseconds 40
    }

    [SmokeTrace]::Mark("popup gone $Title")
    $seen.Duration = $watch.Elapsed.TotalSeconds - $shownAt
    return $seen
}

# A red and blue band behind the top center of the work area, where the popup of the fixture tracks appears.
# Not topmost: the popup would stay under it.
function Start-BackdropFixture {
    $workArea = [SmokeNative+RECT]::new()
    [void][SmokeNative]::SystemParametersInfoW(0x30, 0, [ref]$workArea, 0)
    $dpiScale = [SmokeNative]::GetDpiForSystem() / 96
    $width = [int](480 * $dpiScale)
    $height = [int](112 * $dpiScale)
    $x = [int](($workArea.Left + $workArea.Right - $width) / 2)
    return Start-BackdropProcess $x $workArea.Top $width $height
}

function Start-StoreBackdrop {
    $workArea = [SmokeNative+RECT]::new()
    [void][SmokeNative]::SystemParametersInfoW(0x30, 0, [ref]$workArea, 0)
    return Start-BackdropProcess $workArea.Left $workArea.Top ($workArea.Right - $workArea.Left) ($workArea.Bottom - $workArea.Top) -Neutral
}

function Start-BackdropProcess([int] $X, [int] $Y, [int] $Width, [int] $Height, [switch] $Neutral) {
    $readyPath = Join-Path $OutDir 'backdrop-fixture.txt'
    Remove-Item $readyPath -Force -ErrorAction SilentlyContinue
    $fixturePath = Join-Path $PSScriptRoot 'BackdropFixture.ps1'
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$fixturePath`"",
        '-X', $X, '-Y', $Y, '-Width', $Width, '-Height', $Height, '-ReadyPath', "`"$readyPath`"")
    if ($Neutral) { $arguments += '-Neutral' }
    $fixture = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList $arguments
    if (-not (Wait-For { Test-Path $readyPath })) {
        Stop-Process -Id $fixture.Id -Force -ErrorAction SilentlyContinue
        throw 'the backdrop fixture did not start'
    }

    Remove-Item $readyPath -Force
    return $fixture
}

# Returns what the popup of each fixture track did, or nothing when this desktop cannot judge them.
function Watch-FixtureTracks([string] $ScreenshotName, [switch] $AllowDoNotDisturb) {
    # The app starts watching media just after it shows the window, and by design a track that is
    # already playing at that point gets no popup.
    Start-Sleep -Seconds 2

    $statusPath = Join-Path $OutDir 'media-fixture.txt'
    Remove-Item $statusPath -Force -ErrorAction SilentlyContinue
    $fixturePath = Join-Path $PSScriptRoot 'MediaFixture.ps1'
    $backdrop = Start-BackdropFixture
    [SmokeTrace]::Mark('fixture start')
    $fixture = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$fixturePath`"",
        '-AppId', $FixtureAppId, '-FirstTitle', $FirstTrack, '-SecondTitle', $SecondTrack,
        '-Artist', $FixtureArtist, '-StatusPath', "`"$statusPath`"")
    try {
        $first = Watch-Popup $FirstTrack $ScreenshotName
        $second = Watch-Popup $SecondTrack
        [void]$fixture.WaitForExit(15000)
    } finally {
        if (-not $fixture.HasExited) { Stop-Process -Id $fixture.Id -Force }
        Stop-Process -Id $backdrop.Id -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path $statusPath)) { throw 'the media fixture wrote no status' }
    $status = Get-Content $statusPath -Raw | ConvertFrom-StringData
    [SmokeTrace]::Mark("fixture done current first=$($status[$FirstTrack]) second=$($status[$SecondTrack]) shown first=$($first.Shown) second=$($second.Shown) fullscreen first=$($first.FullScreen) second=$($second.FullScreen)")
    Remove-Item $statusPath -Force
    $reason = $null
    if ($status[$FirstTrack] -ne 'True' -or $status[$SecondTrack] -ne 'True') {
        $reason = 'other media playback took over as the current session, so the media checks say nothing; stop it and run again'
    } elseif ($first.FullScreen -or $second.FullScreen) {
        $reason = 'an app went full-screen during the media checks, and the app hides popups then by design; run again without it'
    } elseif (-not $AllowDoNotDisturb -and (Test-DoNotDisturbOn)) {
        $reason = 'do not disturb is on, and the app hides popups then by design; turn it off and run again'
    }

    if ($reason) {
        $script:UnavailableReason = $reason
        Write-Line "SKIP media: $reason"
        return
    }

    return @{ First = $first; Second = $second }
}

# The margin to the work area does not change with the popup size.
function Test-PopupBounds($Bounds, [int] $SizePercent) {
    $workArea = [SmokeNative+RECT]::new()
    [void][SmokeNative]::SystemParametersInfoW(0x30, 0, [ref]$workArea, 0)
    $dpiScale = [SmokeNative]::GetDpiForSystem() / 96
    $margin = 16 * $dpiScale
    $centerX = ($workArea.Left + $workArea.Right) / 2
    $edges = "left $($Bounds.Left), top $($Bounds.Top), right $($Bounds.Right), bottom $($Bounds.Bottom)"
    Check "the $SizePercent% popup settles at the top center of the work area" ([Math]::Abs(($Bounds.Left + $Bounds.Right) / 2 - $centerX) -le 2 -and [Math]::Abs($Bounds.Top - $workArea.Top - $margin) -le 2) $edges

    $sizeScale = $dpiScale * $SizePercent / 100
    Check "the $SizePercent% popup is that share of 360x80 DIP" ([Math]::Abs($Bounds.Right - $Bounds.Left - 360 * $sizeScale) -le 2 -and [Math]::Abs($Bounds.Bottom - $Bounds.Top - 80 * $sizeScale) -le 2) $edges
}

# How far a pixel is from the red half of the backdrop band.
function Get-RedBandDistance($Pixel) {
    return [Math]::Max(255 - $Pixel.R, [Math]::Max($Pixel.G, $Pixel.B))
}

# The share of rows on the left curve of the pill where the step from the band takes more than one pixel.
# The acrylic's own corner radius leaves a hard stair step, so without the alpha mask this is zero.
function Get-PopupEdgeSoftness($Bitmap) {
    $rows = 0
    $softRows = 0
    for ($y = [int]($Bitmap.Height * 0.1); $y -lt [int]($Bitmap.Height * 0.9); $y++) {
        for ($x = 0; $x -lt [int]($Bitmap.Width / 4); $x++) {
            $distance = Get-RedBandDistance $Bitmap.GetPixel($x, $y)
            if ($distance -lt 16) { continue }

            $settled = [Math]::Max((Get-RedBandDistance $Bitmap.GetPixel(($x + 1), $y)), (Get-RedBandDistance $Bitmap.GetPixel(($x + 2), $y)))
            $rows++
            if ($distance / $settled -lt 0.75) { $softRows++ }
            break
        }
    }

    if ($rows -eq 0) { return 0 }
    return $softRows / $rows
}

# Acrylic lets the two colors of the band through, and a solid background looks the same on both sides.
function Test-PopupAcrylic([string] $ScreenshotName) {
    $path = Join-Path $OutDir "$ScreenshotName.png"
    if (-not (Test-Path $path)) {
        Check 'the popup lets what is behind it show through' $false 'no screenshot was taken'
        return
    }

    $bitmap = [System.Drawing.Bitmap]::new($path)
    try {
        # The corners are outside the pill, so they show the band unless another window covers it.
        $red = [System.Drawing.Color]::Red.ToArgb()
        $blue = [System.Drawing.Color]::Blue.ToArgb()
        if ($bitmap.GetPixel(0, 0).ToArgb() -ne $red -or $bitmap.GetPixel($bitmap.Width - 1, 0).ToArgb() -ne $blue) {
            $script:UnavailableReason = 'another window covered the popup backdrop, so the acrylic check says nothing; run again without it'
            Write-Line "SKIP acrylic: $script:UnavailableReason"
            return
        }

        # Above the text and right of the album art.
        $row = [int]($bitmap.Height * 0.12)
        $left = $bitmap.GetPixel([int]($bitmap.Width * 0.25), $row)
        $right = $bitmap.GetPixel([int]($bitmap.Width * 0.75), $row)
        $difference = ([Math]::Abs($left.R - $right.R), [Math]::Abs($left.G - $right.G), [Math]::Abs($left.B - $right.B) | Measure-Object -Maximum).Maximum
        Check 'the popup lets what is behind it show through' ($difference -ge 16) "left ($($left.R),$($left.G),$($left.B)), right ($($right.R),$($right.G),$($right.B)); transparency effects or battery saver can also turn acrylic off"
        $softness = Get-PopupEdgeSoftness $bitmap
        Check 'the popup edge is anti-aliased' ($softness -ge 0.3) ('{0:P0} of the rows on its curve are partly covered' -f $softness)
    } finally {
        $bitmap.Dispose()
    }
}

function Test-Media {
    $expectedName = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').ParseName($FixtureAppId).Name
    Open-Settings
    $tracks = Watch-FixtureTracks 'popup'
    if (-not $tracks) { return }

    $first = $tracks.First
    $second = $tracks.Second
    Check 'a track change shows the popup' $first.Shown
    if ($first.Shown) {
        Check 'the popup disappears after the default 4 seconds' ($first.Duration -ge 3.5 -and $first.Duration -le 5.5) "visible for $($first.Duration) s"
        Check 'the popup does not take focus' (-not $first.StolenFocus)
        Test-PopupBounds $first.Bounds 90

        # WS_EX_TOPMOST, WS_EX_TRANSPARENT, WS_EX_TOOLWINDOW, WS_EX_NOACTIVATE
        $requiredStyles = 0x8 -bor 0x20 -bor 0x80 -bor 0x08000000
        Check 'the popup is topmost, click-through and hidden from Alt+Tab' (($first.ExStyle -band $requiredStyles) -eq $requiredStyles) ('extended style is 0x{0:X8}' -f $first.ExStyle)
        Test-PopupAcrylic 'popup'
    }

    Check 'the next track shows the popup again' $second.Shown

    $row = Wait-For { Get-SettingsElement $FixtureAppId }
    Check 'the app list shows the registered name of a new app' ($row -and $row.Current.Name -eq $expectedName) "expected '$expectedName'"
    if ($row) {
        $row.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView()
        Start-Sleep -Milliseconds 300
        Save-Screenshot (Get-SettingsWindow) 'app-list'
    }
}

function Save-StoreScreenshots {
    if (Test-DoNotDisturbOn) {
        $script:UnavailableReason = 'do not disturb is on, and the app hides popups then by design; turn it off and run again'
        Write-Line "SKIP storeshots: $script:UnavailableReason"
        return
    }

    $albumPaths = @(1..3 | ForEach-Object { Join-Path $OutDir "store-album-art-$_.png" })
    try {
        # Original artwork without another company's album art or trademarks.
        $colors = @(
            @('#76C7C0', '#274B6D'),
            @('#F59E0B', '#BE185D'),
            @('#A78BFA', '#1E3A8A'))
        for ($i = 0; $i -lt 3; $i++) {
            $bitmap = [System.Drawing.Bitmap]::new(512, 512)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
                [System.Drawing.Rectangle]::new(0, 0, 512, 512),
                [System.Drawing.ColorTranslator]::FromHtml($colors[$i][0]),
                [System.Drawing.ColorTranslator]::FromHtml($colors[$i][1]),
                [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
            try {
                $graphics.FillRectangle($brush, 0, 0, 512, 512)
                $bitmap.Save($albumPaths[$i], [System.Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $brush.Dispose()
                $graphics.Dispose()
                $bitmap.Dispose()
            }
        }

        $languages = @(
            @{ Culture = 'ko-KR'; Titles = @('파도 소리', '섬의 아침', '노을 산책'); Artist = '소리섬 데모' },
            @{ Culture = 'en-US'; Titles = @('Ocean Waves', 'Island Morning', 'Sunset Walk'); Artist = 'Soriseom Demo' })
        $themes = @('ThemeLight', 'ThemeDark', 'ThemeLight')
        foreach ($language in $languages) {
            $culture = $language.Culture
            $fixture = $null
            $backdrop = $null
            $statusPath = Join-Path $OutDir "store-$culture-fixture.txt"
            try {
                Stop-App
                [void](Invoke-LanguageOverride $culture)
                Open-Settings
                # Capture the largest available popup material.
                (Get-SettingsElement 'PopupSizeSlider').GetCurrentPattern($RangeValuePattern).SetValue(100)
                $workArea = [SmokeNative+RECT]::new()
                [void][SmokeNative]::SystemParametersInfoW(0x30, 0, [ref]$workArea, 0)
                $dpiScale = [SmokeNative]::GetDpiForSystem() / 96
                # Keep settings away from the top-center acrylic popup so its colors cannot bleed through.
                $settings = Get-SettingsWindow
                Check "the $culture settings window is available before popup capture" ([bool]$settings)
                if (-not $settings) { continue }
                [void][SmokeNative]::SetWindowPos([IntPtr]$settings.Current.NativeWindowHandle, [IntPtr]::Zero,
                    [int]($workArea.Left + 40 * $dpiScale), [int]($workArea.Top + 200 * $dpiScale), 0, 0, (0x1 -bor 0x4 -bor 0x10))
                $backdrop = Start-StoreBackdrop
                # Tracks already playing when media watching starts get no popup.
                Start-Sleep -Seconds 2
                $fixturePath = Join-Path $PSScriptRoot 'MediaFixture.ps1'
                $popupGone = $true
                foreach ($n in 1..3) {
                    # Do not let the next track replace a popup that failed to disappear.
                    if (-not $popupGone) { break }
                    Select-ComboBoxItem 'ThemeComboBox' $themes[$n - 1]
                    $title = $language.Titles[$n - 1]
                    $fixture = $null
                    try {
                        # Repeating the title prevents a second popup even if stopping the fixture is delayed.
                        $fixture = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
                            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$fixturePath`"",
                            '-AppId', $StoreFixtureAppId, '-FirstTitle', "`"$title`"", '-SecondTitle', "`"$title`"",
                            '-Artist', "`"$($language.Artist)`"", '-ThumbnailPath', "`"$($albumPaths[$n - 1])`"", '-StatusPath', "`"$statusPath`"")
                        $popup = Wait-For {
                            $candidate = Get-PopupWindow
                            if ($candidate -and (Find-Id $candidate 'TitleText').Current.Name -ceq $title) { $candidate }
                        } 12000
                        Check "the $culture demo popup $n appears" ([bool]$popup)
                        if (-not $popup) { continue }

                        Start-Sleep -Milliseconds 1500
                        # A real session could replace the demo during the animation. Never print its title or capture it.
                        $stillDemo = try {
                            $popup = Get-PopupWindow
                            $popup -and (Find-Id $popup 'TitleText').Current.Name -ceq $title
                        } catch { $false }
                        Check "the $culture popup $n still shows the demo before capture" $stillDemo
                        if (-not $stillDemo) { continue }
                        Save-ElementScreenshot $popup "store-material-$culture-popup-$n"

                        $bounds = [SmokeNative+RECT]::new()
                        [void][SmokeNative]::GetWindowRect([IntPtr]$popup.Current.NativeWindowHandle, [ref]$bounds)
                        Check "the $culture popup $n is 360x80 DIP" ([Math]::Abs($bounds.Right - $bounds.Left - 360 * $dpiScale) -le 2 -and [Math]::Abs($bounds.Bottom - $bounds.Top - 80 * $dpiScale) -le 2)
                    } finally {
                        if ($fixture -and -not $fixture.HasExited) { Stop-Process -Id $fixture.Id -Force -ErrorAction SilentlyContinue }
                        $popupGone = Wait-For { -not (Get-PopupWindow) }
                        Check "the $culture popup $n disappears before the next capture" ([bool]$popupGone)
                    }
                }
                if (-not $popupGone) { continue }

                Select-ComboBoxItem 'ThemeComboBox' 'ThemeLight'
                $row = Wait-For { Get-SettingsElement $StoreFixtureAppId }
                Check "the $culture settings show the demo app row" ([bool]$row)
                if (-not $row) { continue }
                $row.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView()
                $settings = Wait-For { Get-SettingsWindow }
                Check "the $culture settings window is available for capture" ([bool]$settings)
                if (-not $settings) { continue }

                $width = [int](720 * $dpiScale)
                $height = [int][Math]::Min(1040 * $dpiScale, $workArea.Bottom - $workArea.Top - 80 * $dpiScale)
                $x = [int](($workArea.Left + $workArea.Right - $width) / 2)
                $y = [int](($workArea.Top + $workArea.Bottom - $height) / 2)
                # HWND_TOPMOST, SWP_NOACTIVATE. Keep the neutral backdrop behind settings.
                $positioned = [SmokeNative]::SetWindowPos([IntPtr]$settings.Current.NativeWindowHandle, [IntPtr]::new(-1), $x, $y, $width, $height, 0x10)
                Check "the $culture settings window is centered above the backdrop" $positioned
                if (-not $positioned) { continue }
                Start-Sleep -Milliseconds 500
                # Fit the visible frame to the last card instead of leaving empty space below it.
                $targetBottom = $row.Current.BoundingRectangle.Bottom + 41 * $dpiScale # Card padding 16 + border 1 + page padding 24.
                $frame = [SmokeNative+RECT]::new()
                $handle = [IntPtr]$settings.Current.NativeWindowHandle
                $result = [SmokeNative]::DwmGetWindowAttribute($handle, 9, [ref]$frame, 16)
                if ($result -ne 0) { throw "DwmGetWindowAttribute failed: $result" }
                if ($frame.Bottom -gt $targetBottom) {
                    $rect = [SmokeNative+RECT]::new()
                    [void][SmokeNative]::GetWindowRect($handle, [ref]$rect)
                    $height = [int]($rect.Bottom - $rect.Top - ($frame.Bottom - $targetBottom))
                    $resized = [SmokeNative]::SetWindowPos($handle, [IntPtr]::Zero, 0, 0, ($rect.Right - $rect.Left), $height, (0x2 -bor 0x4 -bor 0x10))
                    Check "the $culture settings window fits its content" $resized
                    if (-not $resized) { continue }
                    Start-Sleep -Milliseconds 500
                }

                $settings = Get-SettingsWindow
                Check "the $culture settings window is still available for capture" ([bool]$settings)
                if (-not $settings) { continue }
                Save-WindowFrameScreenshot $settings "store-material-$culture-settings"
            } finally {
                if ($fixture -and -not $fixture.HasExited) { Stop-Process -Id $fixture.Id -Force -ErrorAction SilentlyContinue }
                if ($backdrop -and -not $backdrop.HasExited) { Stop-Process -Id $backdrop.Id -Force -ErrorAction SilentlyContinue }
                Remove-Item -LiteralPath $statusPath -Force -ErrorAction SilentlyContinue
            }
        }
    } finally {
        Remove-Item -LiteralPath $albumPaths -Force -ErrorAction SilentlyContinue
    }
}

function Test-PopupSize {
    Open-Settings
    (Get-SettingsElement 'PopupSizeSlider').GetCurrentPattern($RangeValuePattern).SetValue(70)
    $tracks = Watch-FixtureTracks 'popup-small'
    if (-not $tracks) { return }

    Check 'a track change shows the popup at the chosen size' $tracks.First.Shown
    if ($tracks.First.Shown) { Test-PopupBounds $tracks.First.Bounds 70 }

    Restart-App
    $slider = (Get-SettingsElement 'PopupSizeSlider').GetCurrentPattern($RangeValuePattern)
    Check 'the chosen popup size survives a restart' ($slider.Current.Value -eq 70) "slider is at $($slider.Current.Value)"
    $slider.SetValue(90)
}

# Windows apps follow this mode. The taskbar and the tray icon follow SystemUsesLightTheme instead.
function Test-AppsUseLightTheme {
    $key = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
    # Windows starts in light mode, so a missing value means light.
    return $null -eq $key.AppsUseLightTheme -or $key.AppsUseLightTheme -ne 0
}

# Rec. 709 luma from 0 to 255. Light and dark theme surfaces land far on either side of 128.
function Get-Luma($Pixel) {
    return 0.2126 * $Pixel.R + 0.7152 * $Pixel.G + 0.0722 * $Pixel.B
}

# The middle of the title bar, and the left padding of the content halfway down, which no card covers at any scroll position.
# The default title bar is the non-client area above the client area. The scroll viewer is not used for this,
# because UI Automation moves its bounds with the scroll offset. PrintWindow puts the top left corner of the window rect at 0,0.
function Get-SettingsWindowLuma {
    $window = Get-SettingsWindow
    $handle = [IntPtr]$window.Current.NativeWindowHandle
    $rect = [SmokeNative+RECT]::new()
    [void][SmokeNative]::GetWindowRect($handle, [ref]$rect)
    $client = [SmokeNative+RECT]::new()
    [void][SmokeNative]::GetClientRect($handle, [ref]$client)
    $origin = [SmokeNative+POINT]::new()
    [void][SmokeNative]::ClientToScreen($handle, [ref]$origin)
    $left = $origin.X - $rect.Left
    $top = $origin.Y - $rect.Top
    $dpiScale = [SmokeNative]::GetDpiForSystem() / 96
    $bitmap = Get-WindowBitmap $window
    try {
        return @{
            TitleBar = Get-Luma ($bitmap.GetPixel([int]($left + $client.Right / 2), [int]($top / 2)))
            Background = Get-Luma ($bitmap.GetPixel([int]($left + 12 * $dpiScale), [int]($top + $client.Bottom / 2)))
        }
    } finally {
        $bitmap.Dispose()
    }
}

# Waits because the theme can land a frame after the choice. Windows draws the title bar outside XAML, so it is checked on its own.
function Assert-SettingsTheme([string] $Name, [bool] $Light, [string] $ScreenshotName) {
    $script:SettingsLuma = $null
    [void](Wait-For {
        $script:SettingsLuma = Get-SettingsWindowLuma
        (($script:SettingsLuma.Background -ge 128) -eq $Light) -and (($script:SettingsLuma.TitleBar -ge 128) -eq $Light)
    })
    Save-Screenshot (Get-SettingsWindow) $ScreenshotName
    $luma = $script:SettingsLuma
    if (-not $luma) {
        Check $Name $false 'the settings window could not be read'
        return
    }

    Check $Name (($luma.Background -ge 128) -eq $Light) "background luma $([int]$luma.Background)"
    Check "$Name, title bar included" (($luma.TitleBar -ge 128) -eq $Light) "title bar luma $([int]$luma.TitleBar)"
}

# The pixels of the acrylic check, above the text and right of the album art, averaged over both colors of the band.
function Get-PopupLuma([string] $ScreenshotName) {
    $path = Join-Path $OutDir "$ScreenshotName.png"
    if (-not (Test-Path $path)) { return $null }

    $bitmap = [System.Drawing.Bitmap]::new($path)
    try {
        $row = [int]($bitmap.Height * 0.12)
        $left = Get-Luma ($bitmap.GetPixel([int]($bitmap.Width * 0.25), $row))
        $right = Get-Luma ($bitmap.GetPixel([int]($bitmap.Width * 0.75), $row))
        return ($left + $right) / 2
    } finally {
        $bitmap.Dispose()
    }
}

# Chooses the mode Windows is not in, so the check cannot pass by following Windows.
function Test-Theme {
    $systemLight = Test-AppsUseLightTheme
    $chosenLight = -not $systemLight
    $systemName = if ($systemLight) { 'light' } else { 'dark' }
    $chosenName = if ($chosenLight) { 'light' } else { 'dark' }
    $chosenItem = if ($chosenLight) { 'ThemeLight' } else { 'ThemeDark' }

    Open-Settings
    Assert-SettingsTheme "the settings window follows the $systemName Windows mode by default" $systemLight 'theme-default'
    Select-ComboBoxItem 'ThemeComboBox' $chosenItem
    Assert-SettingsTheme "choosing $chosenName applies to the settings window right away" $chosenLight 'theme-chosen'

    $tracks = Watch-FixtureTracks 'popup-theme'
    if ($tracks) {
        Check 'a track change shows the popup in the chosen theme' $tracks.First.Shown
        if ($tracks.First.Shown) {
            $luma = Get-PopupLuma 'popup-theme'
            Check "the popup uses the $chosenName theme" ($null -ne $luma -and ($luma -ge 128) -eq $chosenLight) "luma $luma"
        }
    }

    Restart-App
    Assert-SettingsTheme "the $chosenName theme stays after a restart" $chosenLight 'theme-restarted'
    Select-ComboBoxItem 'ThemeComboBox' 'ThemeSystem'
    Assert-SettingsTheme "choosing the system setting follows the $systemName Windows mode again" $systemLight 'theme-system'
}

function Test-DoNotDisturb {
    if (Test-DoNotDisturbOn) {
        $script:UnavailableReason = 'do not disturb is already on, and this scenario has to turn it on itself; turn it off and run again'
        Write-Line "SKIP dnd: $($script:UnavailableReason)"
        return
    }

    Open-Settings
    Set-Content $DoNotDisturbMarker ''
    try {
        Set-DoNotDisturb $true
        $hidden = Watch-FixtureTracks -AllowDoNotDisturb
    } finally {
        Set-DoNotDisturb $false
        Remove-Item $DoNotDisturbMarker -Force
    }

    if (-not $hidden) { return }
    Check 'do not disturb hides the popup' (-not $hidden.First.Shown -and -not $hidden.Second.Shown)

    $shown = Watch-FixtureTracks
    if ($shown) { Check 'the popup shows again after do not disturb ends' $shown.First.Shown }
}

function Get-TaskbarPart([string] $ClassName) {
    $condition = [System.Windows.Automation.PropertyCondition]::new($Ae::ClassNameProperty, $ClassName)
    $Ae::RootElement.FindFirst($Scope::Children, $condition)
}

# Names of other tray icons stay out of the output.
function Get-TrayIcon {
    $names = (Get-Resource 'ko-KR' 'AppDisplayName'), (Get-Resource 'en-US' 'AppDisplayName')
    $condition = [System.Windows.Automation.PropertyCondition]::new($Ae::AutomationIdProperty, 'NotifyItemIcon')
    foreach ($className in 'Shell_TrayWnd', 'TopLevelWindowForOverflowXamlIsland') {
        $part = Get-TaskbarPart $className
        if (-not $part) { continue }
        foreach ($icon in $part.FindAll($Scope::Descendants, $condition)) {
            $bounds = $icon.Current.BoundingRectangle
            # The overflow keeps its icons in the tree with empty bounds while it is closed.
            if ($icon.Current.Name.Trim() -in $names -and -not $bounds.IsEmpty -and -not [double]::IsNaN($bounds.X)) { return $icon }
        }
    }
}

function Switch-TrayOverflow {
    $condition = [System.Windows.Automation.PropertyCondition]::new($Ae::AutomationIdProperty, 'SystemTrayIcon')
    foreach ($button in (Get-TaskbarPart 'Shell_TrayWnd').FindAll($Scope::Descendants, $condition)) {
        if ($button.Current.Name -match '숨겨진 아이콘|hidden icons') {
            $button.GetCurrentPattern($InvokePattern).Invoke()
            return
        }
    }

    throw 'the tray overflow button was not found'
}

function Test-Tray {
    Open-Settings
    Close-Settings
    $icon = Get-TrayIcon
    $openedOverflow = -not $icon
    if ($openedOverflow) {
        Switch-TrayOverflow
        $icon = Wait-For { Get-TrayIcon } 3000
    }

    Check 'the tray icon is present' ([bool]$icon)
    if (-not $icon) {
        if ($openedOverflow) { Switch-TrayOverflow }
        return
    }

    Save-ElementScreenshot $icon 'tray-icon'
    $icon.GetCurrentPattern($InvokePattern).Invoke()
    Check 'clicking the tray icon opens settings' ([bool](Wait-For { Get-SettingsWindow }))
}

function Test-AfterSignIn {
    $package = Get-AppxPackage -Name $PackageName
    if (-not $package) { throw "package $PackageName is not registered" }
    Set-PackagePaths $package.PackageFamilyName

    Check 'the startup task is enabled' ((Get-StartupState) -eq $StartupEnabled) "state is $(Get-StartupState)"
    $process = Get-AppProcess
    Check 'the app is running' ($process.Count -eq 1) "$($process.Count) processes"
    if ($process.Count -ne 1) { return }

    Check 'no settings window is open' (-not (Get-SettingsWindow))
    $shell = Get-Process -Name explorer | Sort-Object StartTime | Select-Object -First 1
    $minutes = ($process[0].StartTime - $shell.StartTime).TotalMinutes
    Check 'the app started within 5 minutes of the shell' ($minutes -ge 0 -and $minutes -le 5) "app $($process[0].StartTime), shell $($shell.StartTime)"
}

$reason = Get-UnavailableReason
if ($reason) {
    Write-Line "UNAVAILABLE $reason"
    exit 3
}

if ($AfterSignIn) {
    Test-AfterSignIn
    exit $(if ($script:FailedChecks) { 1 } else { 0 })
}

$scenarios = [ordered]@{
    launch = { Test-Launch }
    relaunch = { Test-Relaunch }
    startup = { Test-Startup }
    language = { Test-Language }
    media = { Test-Media }
    popupsize = { Test-PopupSize }
    theme = { Test-Theme }
    dnd = { Test-DoNotDisturb }
    tray = { Test-Tray }
    storeshots = { Save-StoreScreenshots }
}
$selected = $Scenario -split ','
$unknown = $selected | Where-Object { -not $scenarios.Contains($_) }
if ($unknown) { throw "unknown scenario: $unknown. Choose from: $($scenarios.Keys -join ', ')" }

if (-not $OutDir) { $OutDir = Join-Path ([IO.Path]::GetTempPath()) "soriseom-smoke-$(Get-Date -Format yyyyMMdd-HHmmss)" }
[void](New-Item -ItemType Directory -Force -Path $OutDir)
$OutDir = (Resolve-Path $OutDir).Path
$TracePath = Join-Path $OutDir 'app-trace.log'
try {
    [SmokeTrace]::Start($TracePath)
} catch {
    Write-Line "app trace unavailable: $($_.Exception.Message)"
}

if (Test-Path $BackupFile) {
    Write-Line 'an earlier run did not finish; restoring its backup first'
    Restore-UserState
}

try {
    $msix = Build-Msix
    Stop-App
    $package = Get-AppxPackage -Name $PackageName
    # Registering again can change the startup state, so a registered package is saved first.
    if ($package) { Save-UserState $package.PackageFamilyName }
    Deploy-Package $msix
    if (-not $package) { Save-UserState (Get-AppxPackage -Name $PackageName).PackageFamilyName }
    # Checks expect default settings. Without these the app starts as on a first launch.
    Remove-SettingsFiles
    [void](Invoke-LanguageOverride '')

    foreach ($name in $selected) {
        Write-Line "--- $name"
        [SmokeTrace]::Mark("scenario $name")
        try {
            & $scenarios[$name]
        } catch {
            Check "scenario $name finished" $false $_.Exception.Message
        }
    }
} catch {
    Check 'build and deploy' $false $_.Exception.Message
} finally {
    if (Test-Path $BackupFile) { Restore-UserState }
}

Write-Line "app trace $TracePath"
if ($script:FailedChecks -eq 0 -and -not $script:UnavailableReason) { exit 0 }

# A desktop that locked mid-run fails checks that say nothing about the code.
$reason = if ($script:FailedChecks -eq 0) { $script:UnavailableReason } else { Get-UnavailableReason }
if ($reason) {
    Write-Line "UNAVAILABLE $reason"
    exit 3
}

Write-Line "$($script:FailedChecks) checks failed"
exit 1
