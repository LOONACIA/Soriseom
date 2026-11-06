# Shows a red/blue test band, or the Store background's middle color (#155488) to blend popup acrylic and edges.
# Runs in its own process because a form needs a message loop, and the smoke script is busy polling.
param(
    [int] $X,
    [int] $Y,
    [int] $Width,
    [int] $Height,
    [string] $ReadyPath,
    [switch] $Neutral
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class BackdropNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
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
if ($Neutral) {
    # The Store composite's middle color makes the popup acrylic and edges blend with its background.
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#155488')
} else {
    $form.BackColor = [System.Drawing.Color]::Red
    $right = New-Object System.Windows.Forms.Panel
    $right.BackColor = [System.Drawing.Color]::Blue
    $right.Bounds = New-Object System.Drawing.Rectangle ([int]($Width / 2)), 0, ($Width - [int]($Width / 2)), $Height
    $form.Controls.Add($right)
}
$form.Add_Shown({
    if ($Neutral) {
        # HWND_TOP, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE. Not topmost: the popup would stay under it.
        [void][BackdropNative]::SetWindowPos($form.Handle, [IntPtr]::Zero, 0, 0, 0, 0, (0x2 -bor 0x1 -bor 0x10))
    }
    Set-Content -LiteralPath $ReadyPath -Value 'ready'
})
try {
    [System.Windows.Forms.Application]::Run($form)
} finally {
    $form.Dispose()
}
