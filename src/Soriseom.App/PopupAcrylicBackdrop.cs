using Microsoft.UI.Composition;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Soriseom.App;

/// <summary>
/// Desktop acrylic that stays on in an inactive window. The popup never takes focus, and DesktopAcrylicBackdrop shows a flat color when the window is inactive.
/// </summary>
internal sealed partial class PopupAcrylicBackdrop : SystemBackdrop
{
    // The system's opacities (0.85 light, 0.96 dark) let almost nothing of a dark screen through.
    // Below these values secondary text drops under 4.5:1 on some backgrounds.
    private const float LightLuminosityOpacity = 0.7f;
    private const float DarkLuminosityOpacity = 0.8f;
    private const float DarkTintOpacity = 0.15f;
    private static readonly Color _lightTint = Color.FromArgb(255, 0xFC, 0xFC, 0xFC);
    private static readonly Color _darkTint = Color.FromArgb(255, 0x2C, 0x2C, 0x2C);
    private readonly SystemBackdropConfiguration _configuration = new() { IsInputActive = true };
    private DesktopAcrylicController? _controller;

    protected override void OnTargetConnected(ICompositionSupportsSystemBackdrop connectedTarget, XamlRoot xamlRoot)
    {
        base.OnTargetConnected(connectedTarget, xamlRoot);
        Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().EnsureSystemDispatcherQueue();
        _controller = new DesktopAcrylicController();
        CopyDisplayState(connectedTarget, xamlRoot);
        _controller.SetSystemBackdropConfiguration(_configuration);
        _controller.AddSystemBackdropTarget(connectedTarget);
    }

    protected override void OnDefaultSystemBackdropConfigurationChanged(ICompositionSupportsSystemBackdrop target, XamlRoot xamlRoot)
    {
        CopyDisplayState(target, xamlRoot);
    }

    protected override void OnTargetDisconnected(ICompositionSupportsSystemBackdrop disconnectedTarget)
    {
        _controller?.RemoveSystemBackdropTarget(disconnectedTarget);
        _controller?.Dispose();
        _controller = null;
        base.OnTargetDisconnected(disconnectedTarget);
    }

    // Everything except IsInputActive, which the default configuration turns off for this window.
    // The tint is set by hand, so it is set again for each theme.
    private void CopyDisplayState(ICompositionSupportsSystemBackdrop target, XamlRoot xamlRoot)
    {
        var current = GetDefaultSystemBackdropConfiguration(target, xamlRoot);
        _configuration.Theme = current.Theme;
        _configuration.IsHighContrast = current.IsHighContrast;
        _configuration.HighContrastBackgroundColor = current.HighContrastBackgroundColor;
        bool isDark = current.Theme == SystemBackdropTheme.Dark;
        _controller!.TintColor = isDark ? _darkTint : _lightTint;
        _controller.TintOpacity = isDark ? DarkTintOpacity : 0;
        _controller.LuminosityOpacity = isDark ? DarkLuminosityOpacity : LightLuminosityOpacity;
    }
}
