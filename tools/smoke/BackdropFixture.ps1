# Shows a red and blue band behind the popup, so the smoke test can tell acrylic from a solid color.
# Runs in its own process because a form needs a message loop, and the smoke script is busy polling.
param(
    [int] $X,
    [int] $Y,
    [int] $Width,
    [int] $Height,
    [string] $ReadyPath
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class BackdropNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
}
public class BackdropForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            // WS_EX_TOOLWINDOW, WS_EX_NOACTIVATE
            CreateParams parameters = base.CreateParams;
            parameters.ExStyle |= 0x80 | 0x08000000;
            return parameters;
        }
    }
}
'@
# Per-monitor aware, so the bounds are the physical pixels the smoke script computed.
[void][BackdropNative]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))

$form = New-Object BackdropForm
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'
$form.Bounds = New-Object System.Drawing.Rectangle $X, $Y, $Width, $Height
$form.BackColor = [System.Drawing.Color]::Red
$right = New-Object System.Windows.Forms.Panel
$right.BackColor = [System.Drawing.Color]::Blue
$right.Bounds = New-Object System.Drawing.Rectangle ([int]($Width / 2)), 0, ($Width - [int]($Width / 2)), $Height
$form.Controls.Add($right)
$form.Add_Shown({ Set-Content -LiteralPath $ReadyPath -Value 'ready' })
[System.Windows.Forms.Application]::Run($form)
