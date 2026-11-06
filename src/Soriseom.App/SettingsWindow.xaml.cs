using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.Windows.ApplicationModel.Resources;
using Soriseom.Core;
using Windows.Graphics;
using Windows.Win32;
using Windows.Win32.Foundation;

namespace Soriseom.App;

public sealed partial class SettingsWindow : Window
{
    private const int WidthDip = 560;
    private const int HeightDip = 640;

    internal SettingsWindow(SettingsStore store)
    {
        ViewModel = new SettingsViewModel(store);
        InitializeComponent();
        Title = new ResourceLoader().GetString("SettingsWindowTitle");
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));

        var hwnd = new HWND(Win32Interop.GetWindowFromWindowId(AppWindow.Id));
        uint dpi = PInvoke.GetDpiForWindow(hwnd);
        double scale = dpi == 0 ? 1.0 : dpi / 96.0;
        AppWindow.Resize(new SizeInt32((int)Math.Round(WidthDip * scale), (int)Math.Round(HeightDip * scale)));

        ApplyTheme(store.Current.Theme);
        store.Changed += (_, _) => ApplyTheme(store.Current.Theme);

        Activated += (sender, args) =>
        {
            if (args.WindowActivationState != WindowActivationState.Deactivated)
            {
                _ = ViewModel.RefreshLaunchAtStartupAsync();
            }
        };

        AppWindow.Closing += (sender, args) =>
        {
            args.Cancel = true;
            sender.Hide();
        };
    }

    public SettingsViewModel ViewModel { get; }

    public void ShowAndActivate()
    {
        if (AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized } presenter)
        {
            presenter.Restore();
        }

        AppWindow.Show();
        Activate();
    }

    // The default title bar is drawn outside XAML, so it takes the theme separately.
    private void ApplyTheme(AppTheme theme)
    {
        ContentRoot.RequestedTheme = theme.ToElementTheme();
        AppWindow.TitleBar.PreferredTheme = theme switch
        {
            AppTheme.Light => TitleBarTheme.Light,
            AppTheme.Dark => TitleBarTheme.Dark,
            _ => TitleBarTheme.UseDefaultAppMode,
        };
    }
}
