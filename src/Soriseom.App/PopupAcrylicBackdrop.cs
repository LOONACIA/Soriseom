using Microsoft.UI.Composition;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Soriseom.App;

/// <summary>
/// Desktop acrylic that stays on in an inactive window. The popup never takes focus, and DesktopAcrylicBackdrop shows a flat color when the window is inactive.
/// </summary>
internal sealed partial class PopupAcrylicBackdrop : SystemBackdrop
{
    private readonly SystemBackdropConfiguration _configuration = new() { IsInputActive = true };
    private DesktopAcrylicController? _controller;

    protected override void OnTargetConnected(ICompositionSupportsSystemBackdrop connectedTarget, XamlRoot xamlRoot)
    {
        base.OnTargetConnected(connectedTarget, xamlRoot);
        Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().EnsureSystemDispatcherQueue();
        CopyDisplayState(connectedTarget, xamlRoot);
        _controller = new DesktopAcrylicController();
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
    private void CopyDisplayState(ICompositionSupportsSystemBackdrop target, XamlRoot xamlRoot)
    {
        var current = GetDefaultSystemBackdropConfiguration(target, xamlRoot);
        _configuration.Theme = current.Theme;
        _configuration.IsHighContrast = current.IsHighContrast;
        _configuration.HighContrastBackgroundColor = current.HighContrastBackgroundColor;
    }
}
