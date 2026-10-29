using System.Diagnostics;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Windows.Win32;

namespace Soriseom.App;

/// <summary>
/// Provides application-specific behavior to supplement the default Application class.
/// </summary>
public partial class App : Application
{
    private const string MainInstanceKey = "main";

    private SettingsWindow? _settingsWindow;
    private TrayController? _trayController;
    private PopupController? _popupController;

    /// <summary>
    /// Initializes a new instance of the <see cref="App"/> class.
    /// Initializes the singleton application object.  This is the first line of authored code
    /// executed, and as such is the logical equivalent of main() or WinMain().
    /// </summary>
    public App()
    {
        InitializeComponent();
    }

    /// <summary>
    /// Invoked when the application is launched.
    /// </summary>
    /// <param name="args">Details about the launch request and process.</param>
    protected override async void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        var mainInstance = AppInstance.FindOrRegisterForKey(MainInstanceKey);
        if (!mainInstance.IsCurrent)
        {
            PInvoke.AllowSetForegroundWindow(mainInstance.ProcessId);
            await mainInstance.RedirectActivationToAsync(AppInstance.GetCurrent().GetActivatedEventArgs());
            Process.GetCurrentProcess().Kill();
            return;
        }

        var dispatcherQueue = DispatcherQueue.GetForCurrentThread();
        mainInstance.Activated += (_, _) => dispatcherQueue.TryEnqueue(ShowSettings);

        _settingsWindow = new SettingsWindow();
        _trayController = new TrayController(ShowSettings, ExitApplication);
        ShowSettings();
        _popupController = new PopupController(dispatcherQueue);
        await _popupController.StartAsync();
    }

    private void ShowSettings() => _settingsWindow?.ShowAndActivate();

    private void ExitApplication()
    {
        _trayController?.Dispose();
        Exit();
    }
}
