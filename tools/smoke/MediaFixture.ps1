# Publishes a muted media session whose track changes once, so the app has something to show.
# Runs under Windows PowerShell 5.1 because pwsh 7 has no WinRT projection.
#
# The app follows only the session Windows calls current, and real playback can take that over at any
# moment. For each track this writes "<title>=True" to StatusPath if this session stayed current, so
# the smoke test can tell a missing popup from a session that was never in front.
param(
    [string] $AppId,
    [string] $FirstTitle,
    [string] $SecondTitle,
    [string] $Artist,
    [string] $StatusPath,
    [int] $HoldSeconds = 8
)

$ErrorActionPreference = 'Stop'

# GSMTC reports this ID as the session's app, which lets the smoke test expect a registered name.
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class FixtureNative {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
[void][FixtureNative]::SetCurrentProcessExplicitAppUserModelID($AppId)

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType = WindowsRuntime]
[void][Windows.Media.Core.MediaSource, Windows.Media, ContentType = WindowsRuntime]
$managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]

$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
$managerTask = $asTask.MakeGenericMethod($managerType).Invoke($null, @($managerType::RequestAsync()))
$managerTask.Wait()
$manager = $managerTask.Result

function Test-StaysCurrent {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $becameCurrentAt = $null
    $lost = $false
    while ($watch.Elapsed.TotalSeconds -lt $HoldSeconds) {
        $current = $manager.GetCurrentSession()
        if ($current -and $current.SourceAppUserModelId -eq $AppId) {
            if ($null -eq $becameCurrentAt) { $becameCurrentAt = $watch.Elapsed.TotalSeconds }
        } elseif ($null -ne $becameCurrentAt) {
            $lost = $true
        }

        Start-Sleep -Milliseconds 100
    }

    return ($null -ne $becameCurrentAt) -and ($becameCurrentAt -lt 2) -and (-not $lost)
}

$player = New-Object Windows.Media.Playback.MediaPlayer
$player.IsMuted = $true
$player.IsLoopingEnabled = $true
$player.Source = [Windows.Media.Core.MediaSource]::CreateFromUri([Uri]"file:///$env:WINDIR/Media/Alarm01.wav")
$player.CommandManager.IsEnabled = $false

$controls = $player.SystemMediaTransportControls
$controls.IsEnabled = $true
$controls.IsPlayEnabled = $true
$controls.IsPauseEnabled = $true
$player.Play()
$controls.PlaybackStatus = [Windows.Media.MediaPlaybackStatus]::Playing

foreach ($title in $FirstTitle, $SecondTitle) {
    $controls.DisplayUpdater.Type = [Windows.Media.MediaPlaybackType]::Music
    $controls.DisplayUpdater.MusicProperties.Title = $title
    $controls.DisplayUpdater.MusicProperties.Artist = $Artist
    $controls.DisplayUpdater.Update()
    Add-Content -Path $StatusPath -Value "$title=$(Test-StaysCurrent)"
}

$player.Pause()
$controls.IsEnabled = $false
$player.Dispose()
