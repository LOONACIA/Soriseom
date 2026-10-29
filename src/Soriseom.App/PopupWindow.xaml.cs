using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Soriseom.Core;
using Windows.Graphics;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Dwm;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.UI.HiDpi;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Soriseom.App;

public sealed partial class PopupWindow : Window
{
    private const int WidthDip = 360;
    private const int HeightDip = 80;
    private const int MarginDip = 16;

    public unsafe PopupWindow()
    {
        InitializeComponent();
        var presenter = OverlappedPresenter.Create();
        presenter.SetBorderAndTitleBar(false, false);
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.IsAlwaysOnTop = true;
        AppWindow.SetPresenter(presenter);

        var hwnd = new HWND(Win32Interop.GetWindowFromWindowId(AppWindow.Id));
        var extendedStyle = (WINDOW_EX_STYLE)PInvoke.GetWindowLong(hwnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);
        extendedStyle |= WINDOW_EX_STYLE.WS_EX_LAYERED | WINDOW_EX_STYLE.WS_EX_TRANSPARENT
            | WINDOW_EX_STYLE.WS_EX_TOOLWINDOW | WINDOW_EX_STYLE.WS_EX_NOACTIVATE;
        PInvoke.SetWindowLong(hwnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE, (int)extendedStyle);
        PInvoke.SetLayeredWindowAttributes(hwnd, new COLORREF(0), 255, LAYERED_WINDOW_ATTRIBUTES_FLAGS.LWA_ALPHA);

        var preference = DWM_WINDOW_CORNER_PREFERENCE.DWMWCP_ROUND;
        PInvoke.DwmSetWindowAttribute(hwnd, DWMWINDOWATTRIBUTE.DWMWA_WINDOW_CORNER_PREFERENCE, &preference, sizeof(DWM_WINDOW_CORNER_PREFERENCE));
    }

    public void ShowTrack(MediaSnapshot track, PopupPosition position)
    {
        TitleText.Text = track.Title;
        ArtistText.Text = track.Artist;

        var display = DisplayArea.Primary;
        var workArea = display.WorkArea;
        var monitor = Win32Interop.GetMonitorFromDisplayId(display.DisplayId);
        var result = PInvoke.GetDpiForMonitor(new HMONITOR(monitor), MONITOR_DPI_TYPE.MDT_EFFECTIVE_DPI, out uint dpiX, out _);
        double scale = result.Failed ? 1.0 : dpiX / 96.0;
        int width = (int)Math.Round(WidthDip * scale);
        int height = (int)Math.Round(HeightDip * scale);
        int margin = (int)Math.Round(MarginDip * scale);
        var bounds = PopupPlacement.Compute(position, new PixelRect(workArea.X, workArea.Y, workArea.Width, workArea.Height), width, height, margin);

        AppWindow.Move(new PointInt32(workArea.X, workArea.Y));
        AppWindow.MoveAndResize(new RectInt32(bounds.X, bounds.Y, bounds.Width, bounds.Height));
        AppWindow.Show(false);
    }

    public void HidePopup()
    {
        AppWindow.Hide();
    }
}
