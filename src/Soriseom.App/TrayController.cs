using System.Diagnostics;
using CommunityToolkit.Mvvm.Input;
using H.NotifyIcon;
using Microsoft.UI;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.Windows.ApplicationModel.Resources;

namespace Soriseom.App;

internal sealed class TrayController : IDisposable
{
    private readonly TaskbarIcon _taskbarIcon;

    public TrayController(Action openSettings, Action exit)
    {
        var loader = new ResourceLoader();
        var menu = new MenuFlyout();
        menu.Items.Add(new MenuFlyoutItem
        {
            Text = loader.GetString("TraySettings"),
            Command = new RelayCommand(openSettings),
        });
        menu.Items.Add(new MenuFlyoutItem
        {
            Text = loader.GetString("TrayExit"),
            Command = new RelayCommand(exit),
        });

        _taskbarIcon = new TaskbarIcon
        {
            ToolTipText = loader.GetString("AppDisplayName"),
            NoLeftClickDelay = true,
            LeftClickCommand = new RelayCommand(openSettings),
            ContextFlyout = menu,
            IconSource = new GeneratedIconSource
            {
                Text = "",
                FontFamily = new FontFamily("Segoe MDL2 Assets"),
                FontSize = 72,
                Foreground = new SolidColorBrush(Colors.White),
                Background = new SolidColorBrush(ColorHelper.FromArgb(255, 0, 103, 192)),
                BackgroundType = BackgroundType.Ellipse,
            },
        };

        try
        {
            _taskbarIcon.ForceCreate(enablesEfficiencyMode: false);
        }
        catch (Exception exception)
        {
            Debug.WriteLine(exception);
        }
    }

    public void Dispose()
    {
        _taskbarIcon.Dispose();
    }
}
