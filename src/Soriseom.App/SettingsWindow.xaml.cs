using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.Windows.ApplicationModel.Resources;
using Windows.Graphics;
using Windows.Win32;
using Windows.Win32.Foundation;

namespace Soriseom.App;

public sealed partial class SettingsWindow : Window
{
    private const int WidthDip = 560;
    private const int HeightDip = 640;

    public SettingsWindow()
    {
        InitializeComponent();
        Title = new ResourceLoader().GetString("SettingsWindowTitle");

        var hwnd = new HWND(Win32Interop.GetWindowFromWindowId(AppWindow.Id));
        uint dpi = PInvoke.GetDpiForWindow(hwnd);
        double scale = dpi == 0 ? 1.0 : dpi / 96.0;
        AppWindow.Resize(new SizeInt32((int)Math.Round(WidthDip * scale), (int)Math.Round(HeightDip * scale)));

        AppWindow.Closing += (sender, args) =>
        {
            args.Cancel = true;
            sender.Hide();
        };
    }

    public void ShowAndActivate()
    {
        if (AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized } presenter)
        {
            presenter.Restore();
        }

        AppWindow.Show();
        Activate();
    }
}
