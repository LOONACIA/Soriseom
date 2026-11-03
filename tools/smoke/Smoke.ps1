#Requires -Version 7
<#
.SYNOPSIS
    Deploys the current build as the dev package and checks the running app through UI Automation.

.DESCRIPTION
    Runs on the live desktop: windows appear and can take focus, and the dev package is registered again.
    Starts from default settings and restores the user's settings and startup state when it ends, including
    on the next run if this one dies.

    Only Claude runs this. Codex must not, see docs/ADR.md ADR-009.

    Exit codes: 0 all checks passed, 1 a check failed, 3 this desktop cannot run the checks right now
    (locked, full-screen, or other media playback holds the current session), which says nothing about the code.

.PARAMETER Scenario
    Comma-separated subset of: launch, relaunch, startup, language, media, tray.

.PARAMETER AfterSignIn
    Read-only check to run after a real sign-in: no build, no deploy, no launch.

.PARAMETER OutDir
    Where screenshots go. Defaults to a new temp directory.

.EXAMPLE
    pwsh -NoProfile -File tools/smoke/Smoke.ps1 -Scenario language,media
#>
param(
    [string] $Scenario = 'launch,relaunch,startup,language,media,tray',
    [switch] $AfterSignIn,
    [string] $OutDir
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SmokeNative {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);
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
$FixtureArtist = 'SmokeArtist'
$FirstTrack = 'SmokeTrackA'
$SecondTrack = 'SmokeTrackB'

# StartupTaskState values as Windows stores them.
$StartupDisabled = 0
$StartupDisabledByUser = 1
$StartupEnabled = 2

$Ae = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]
$TogglePattern = [System.Windows.Automation.TogglePattern]::Pattern
$WindowPattern = [System.Windows.Automation.WindowPattern]::Pattern
$InvokePattern = [System.Windows.Automation.InvokePattern]::Pattern
$ExpandPattern = [System.Windows.Automation.ExpandCollapsePattern]::Pattern
$SelectionPattern = [System.Windows.Automation.SelectionPattern]::Pattern
$SelectionItemPattern = [System.Windows.Automation.SelectionItemPattern]::Pattern

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

    Remove-Item $BackupDir -Recurse -Force
    Write-Line 'restored the settings and startup state from before this run'
}

function Build-Msix {
    $output = & dotnet build $AppProject -p:Platform=x64 -p:GenerateAppxPackageOnBuild=true -p:AppxPackageSigningEnabled=false -v q 2>&1
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

# Settings windows carry an invisible resize border that PrintWindow renders as black bands on three sides.
function Save-Screenshot($Window, [string] $Name) {
    $handle = [IntPtr]$Window.Current.NativeWindowHandle
    $rect = [SmokeNative+RECT]::new()
    [void][SmokeNative]::GetWindowRect($handle, [ref]$rect)
    $bitmap = [System.Drawing.Bitmap]::new($rect.Right - $rect.Left, $rect.Bottom - $rect.Top)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    [void][SmokeNative]::PrintWindow($handle, $hdc, 2)
    $graphics.ReleaseHdc($hdc)
    $graphics.Dispose()
    $path = Join-Path $OutDir "$Name.png"
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
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

function Select-Language([string] $ItemId) {
    $combo = Get-SettingsElement 'LanguageComboBox'
    $combo.GetCurrentPattern($ExpandPattern).Expand()
    $item = Wait-For { Find-Id $combo $ItemId }
    if (-not $item) { throw "language item $ItemId did not appear" }
    $item.GetCurrentPattern($SelectionItemPattern).Select()
    $isSelected = {
        $selection = (Get-SettingsElement 'LanguageComboBox').GetCurrentPattern($SelectionPattern).Current.GetSelection()
        $selection.Count -eq 1 -and $selection[0].Current.AutomationId -eq $ItemId
    }
    if (-not (Wait-For $isSelected)) { throw "language item $ItemId was not selected" }
    $isCollapsed = {
        $state = (Get-SettingsElement 'LanguageComboBox').GetCurrentPattern($ExpandPattern)
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
    Select-Language $otherItem
    Check 'choosing another language shows the restart notice' ([bool](Wait-For { Get-SettingsElement 'LanguageRestartNotice' }))
    Save-Screenshot (Get-SettingsWindow) 'language-notice'
    Select-Language 'LanguageSystem'
    Check 'choosing the launch language hides the restart notice' ([bool](Wait-For { -not (Get-SettingsElement 'LanguageRestartNotice') }))

    Select-Language $otherItem
    Restart-App
    $expected = Get-Resource $otherCulture 'SettingsHeader.Text'
    Check 'the chosen language applies after a restart' ([bool](Wait-For { (& $header) -eq $expected })) "header is '$(& $header)'"
    Save-Screenshot (Get-SettingsWindow) 'language-applied'

    Select-Language 'LanguageSystem'
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

    if (-not $popup) { return $seen }

    # From here on only Win32 state decides: a UI Automation read can fail for a moment while the window is up.
    $seen.Shown = $true
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
                Save-Screenshot $popup $ScreenshotName
                $screenshotTaken = $true
            }
        }

        Start-Sleep -Milliseconds 40
    }

    $seen.Duration = $watch.Elapsed.TotalSeconds - $shownAt
    return $seen
}

function Test-Media {
    $expectedName = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').ParseName($FixtureAppId).Name
    Open-Settings
    # The app starts watching media just after it shows the window, and by design a track that is
    # already playing at that point gets no popup.
    Start-Sleep -Seconds 2

    $statusPath = Join-Path $OutDir 'media-fixture.txt'
    Remove-Item $statusPath -Force -ErrorAction SilentlyContinue
    $fixturePath = Join-Path $PSScriptRoot 'MediaFixture.ps1'
    $fixture = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$fixturePath`"",
        '-AppId', $FixtureAppId, '-FirstTitle', $FirstTrack, '-SecondTitle', $SecondTrack,
        '-Artist', $FixtureArtist, '-StatusPath', "`"$statusPath`"")
    try {
        $first = Watch-Popup $FirstTrack 'popup'
        $second = Watch-Popup $SecondTrack
        [void]$fixture.WaitForExit(15000)
    } finally {
        if (-not $fixture.HasExited) { Stop-Process -Id $fixture.Id -Force }
    }

    if (-not (Test-Path $statusPath)) { throw 'the media fixture wrote no status' }
    $status = Get-Content $statusPath -Raw | ConvertFrom-StringData
    Remove-Item $statusPath -Force
    if ($status[$FirstTrack] -ne 'True' -or $status[$SecondTrack] -ne 'True') {
        $script:UnavailableReason = 'other media playback took over as the current session, so the media checks say nothing; stop it and run again'
    } elseif ($first.FullScreen -or $second.FullScreen) {
        $script:UnavailableReason = 'an app went full-screen during the media checks, and the app hides popups then by design; run again without it'
    }

    if ($script:UnavailableReason) {
        Write-Line "SKIP media: $($script:UnavailableReason)"
        return
    }

    Check 'a track change shows the popup' $first.Shown
    if ($first.Shown) {
        Check 'the popup disappears after the default 4 seconds' ($first.Duration -ge 3.5 -and $first.Duration -le 5.5) "visible for $($first.Duration) s"
        Check 'the popup does not take focus' (-not $first.StolenFocus)

        $workArea = [SmokeNative+RECT]::new()
        [void][SmokeNative]::SystemParametersInfoW(0x30, 0, [ref]$workArea, 0)
        $margin = 16 * [SmokeNative]::GetDpiForSystem() / 96
        $centerX = ($workArea.Left + $workArea.Right) / 2
        $bounds = $first.Bounds
        Check 'the popup settles at the top center of the work area' ([Math]::Abs(($bounds.Left + $bounds.Right) / 2 - $centerX) -le 2 -and [Math]::Abs($bounds.Top - $workArea.Top - $margin) -le 2) "left $($bounds.Left), top $($bounds.Top), right $($bounds.Right)"

        # WS_EX_TOPMOST, WS_EX_TRANSPARENT, WS_EX_TOOLWINDOW, WS_EX_NOACTIVATE
        $requiredStyles = 0x8 -bor 0x20 -bor 0x80 -bor 0x08000000
        Check 'the popup is topmost, click-through and hidden from Alt+Tab' (($first.ExStyle -band $requiredStyles) -eq $requiredStyles) ('extended style is 0x{0:X8}' -f $first.ExStyle)
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
    tray = { Test-Tray }
}
$selected = $Scenario -split ','
$unknown = $selected | Where-Object { -not $scenarios.Contains($_) }
if ($unknown) { throw "unknown scenario: $unknown. Choose from: $($scenarios.Keys -join ', ')" }

if (-not $OutDir) { $OutDir = Join-Path ([IO.Path]::GetTempPath()) "soriseom-smoke-$(Get-Date -Format yyyyMMdd-HHmmss)" }
[void](New-Item -ItemType Directory -Force -Path $OutDir)
$OutDir = (Resolve-Path $OutDir).Path

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

if ($script:FailedChecks -eq 0 -and -not $script:UnavailableReason) { exit 0 }

# A desktop that locked mid-run fails checks that say nothing about the code.
$reason = if ($script:FailedChecks -eq 0) { $script:UnavailableReason } else { Get-UnavailableReason }
if ($reason) {
    Write-Line "UNAVAILABLE $reason"
    exit 3
}

Write-Line "$($script:FailedChecks) checks failed"
exit 1
