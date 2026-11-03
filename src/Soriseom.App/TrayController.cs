using System.Diagnostics;
using CommunityToolkit.Mvvm.Input;
using H.NotifyIcon;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.Win32;
using Microsoft.Windows.ApplicationModel.Resources;
using Windows.UI.ViewManagement;

namespace Soriseom.App;

internal sealed class TrayController : IDisposable
{
    private readonly TaskbarIcon _taskbarIcon;
    private readonly DispatcherQueue _dispatcherQueue = DispatcherQueue.GetForCurrentThread();
    private readonly UISettings _uiSettings = new();
    private bool _isTaskbarLight;

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

        _isTaskbarLight = IsTaskbarLight();
        _taskbarIcon = new TaskbarIcon
        {
            ToolTipText = loader.GetString("AppDisplayName"),
            NoLeftClickDelay = true,
            LeftClickCommand = new RelayCommand(openSettings),
            ContextFlyout = menu,
            IconSource = CreateIcon(_isTaskbarLight),
        };

        try
        {
            _taskbarIcon.ForceCreate(enablesEfficiencyMode: false);
        }
        catch (Exception exception)
        {
            Debug.WriteLine(exception);
        }

        _uiSettings.ColorValuesChanged += OnColorValuesChanged;
    }

    public void Dispose()
    {
        _uiSettings.ColorValuesChanged -= OnColorValuesChanged;
        _taskbarIcon.Dispose();
    }

    private static bool IsTaskbarLight()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("SystemUsesLightTheme") is int value && value != 0;
        }
        catch (Exception exception)
        {
            Debug.WriteLine(exception);
            return false;
        }
    }

    private static BitmapImage CreateIcon(bool isTaskbarLight)
    {
        return new BitmapImage(new Uri(isTaskbarLight
            ? "ms-appx:///Assets/TrayIconForLightTaskbar.ico"
            : "ms-appx:///Assets/TrayIconForDarkTaskbar.ico"));
    }

    private void OnColorValuesChanged(UISettings sender, object args)
    {
        _dispatcherQueue.TryEnqueue(UpdateIcon);
    }

    private void UpdateIcon()
    {
        var isTaskbarLight = IsTaskbarLight();
        if (isTaskbarLight != _isTaskbarLight)
        {
            _isTaskbarLight = isTaskbarLight;
            _taskbarIcon.IconSource = CreateIcon(_isTaskbarLight);
        }
    }
}
