using System.Diagnostics;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Soriseom.Core;
using Windows.Graphics;
using Windows.Storage.Streams;
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
    private readonly DispatcherQueueTimer _animationTimer;
    private readonly Stopwatch _animationStopwatch = new();
    private PointInt32 _finalPosition;
    private int _slideOffset;
    private bool _isVisible;
    private bool _isFadingOut;
    private long _thumbnailVersion;

    public unsafe PopupWindow()
    {
        InitializeComponent();
        _animationTimer = DispatcherQueue.CreateTimer();
        _animationTimer.IsRepeating = true;
        _animationTimer.Interval = TimeSpan.FromMilliseconds(16);
        _animationTimer.Tick += (_, _) => Animate();
        Closed += (_, _) =>
        {
            _animationTimer.Stop();
            _animationStopwatch.Stop();
        };
        AlbumArtBrush.ImageFailed += (_, args) =>
        {
            Debug.WriteLine(args.ErrorMessage);
            ShowNoteArt();
        };
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

    public void ShowTrack(MediaSnapshot track, IRandomAccessStreamReference? thumbnail, PopupPosition position)
    {
        TitleText.Text = track.Title;
        ArtistText.Text = track.Artist;
        ShowNoteArt();

        var display = DisplayArea.Primary;
        var workArea = display.WorkArea;
        var monitor = Win32Interop.GetMonitorFromDisplayId(display.DisplayId);
        var result = PInvoke.GetDpiForMonitor(new HMONITOR(monitor), MONITOR_DPI_TYPE.MDT_EFFECTIVE_DPI, out uint dpiX, out _);
        double scale = result.Failed ? 1.0 : dpiX / 96.0;
        int width = (int)Math.Round(WidthDip * scale);
        int height = (int)Math.Round(HeightDip * scale);
        int margin = (int)Math.Round(MarginDip * scale);
        var bounds = PopupPlacement.Compute(position, new PixelRect(workArea.X, workArea.Y, workArea.Width, workArea.Height), width, height, margin);

        _animationTimer.Stop();
        _animationStopwatch.Reset();
        _finalPosition = new PointInt32(bounds.X, bounds.Y);
        if (!_isVisible)
        {
            SetAlpha(0);
            AppWindow.Move(new PointInt32(workArea.X, workArea.Y));
        }

        AppWindow.MoveAndResize(new RectInt32(bounds.X, bounds.Y, bounds.Width, bounds.Height));
        if (_isVisible)
        {
            SetAlpha(255);
        }
        else
        {
            _slideOffset = (int)Math.Round(24 * scale);
            if (position is PopupPosition.TopLeft or PopupPosition.TopCenter or PopupPosition.TopRight)
            {
                _slideOffset = -_slideOffset;
            }

            AppWindow.Move(new PointInt32(_finalPosition.X, _finalPosition.Y + _slideOffset));
            _isFadingOut = false;
            _animationStopwatch.Restart();
            _animationTimer.Start();
        }

        _isVisible = true;
        AppWindow.Show(false);
        _ = LoadThumbnailAsync(thumbnail);
    }

    public void UpdateThumbnail(IRandomAccessStreamReference? thumbnail)
    {
        _ = LoadThumbnailAsync(thumbnail);
    }

    public void HidePopup()
    {
        if (!_isVisible)
        {
            return;
        }

        _animationTimer.Stop();
        _isFadingOut = true;
        SetAlpha(255);
        _animationStopwatch.Restart();
        _animationTimer.Start();
    }

    private void Animate()
    {
        if (!_animationTimer.IsRunning)
        {
            return;
        }

        double duration = _isFadingOut ? 200 : 250;
        double progress = Math.Min(_animationStopwatch.Elapsed.TotalMilliseconds / duration, 1);
        if (_isFadingOut)
        {
            SetAlpha((byte)Math.Round(255 * (1 - progress)));
        }
        else
        {
            double eased = 1 - Math.Pow(1 - progress, 3);
            AppWindow.Move(new PointInt32(_finalPosition.X, _finalPosition.Y + (int)Math.Round(_slideOffset * (1 - eased))));
            SetAlpha((byte)Math.Round(255 * eased));
        }

        if (progress >= 1)
        {
            _animationTimer.Stop();
            _animationStopwatch.Stop();
            if (_isFadingOut)
            {
                AppWindow.Hide();
                _isVisible = false;
                SetAlpha(255);
            }
        }
    }

    private void SetAlpha(byte alpha)
    {
        var hwnd = new HWND(Win32Interop.GetWindowFromWindowId(AppWindow.Id));
        PInvoke.SetLayeredWindowAttributes(hwnd, new COLORREF(0), alpha, LAYERED_WINDOW_ATTRIBUTES_FLAGS.LWA_ALPHA);
    }

    private async Task LoadThumbnailAsync(IRandomAccessStreamReference? thumbnail)
    {
        var version = ++_thumbnailVersion;
        if (thumbnail is null)
        {
            ShowNoteArt();
            return;
        }

        try
        {
            using var stream = await thumbnail.OpenReadAsync();
            var bitmap = new BitmapImage();
            await bitmap.SetSourceAsync(stream);
            if (version != _thumbnailVersion)
            {
                return;
            }

            AlbumArtBrush.ImageSource = bitmap;
            AlbumArt.Visibility = Visibility.Visible;
            NoteArt.Visibility = Visibility.Collapsed;
        }
        catch (Exception exception)
        {
            Debug.WriteLine(exception);
            if (version == _thumbnailVersion)
            {
                ShowNoteArt();
            }
        }
    }

    private void ShowNoteArt()
    {
        AlbumArt.Visibility = Visibility.Collapsed;
        NoteArt.Visibility = Visibility.Visible;
        AlbumArtBrush.ImageSource = null;
    }
}
