using System.Diagnostics;
using System.Numerics;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Media.Imaging;
using Soriseom.Core;
using Windows.Foundation;
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
    private const double BodyFontSizeDip = 14;
    private const double MinVisibleFontSizeDip = 12;
    private const float CollapsedLeftDip = (WidthDip - HeightDip) / 2f;
    private const float CollapsedRightDip = (WidthDip + HeightDip) / 2f;
    private const float HiddenScale = 0.4f;
    private static readonly TimeSpan _appearOpacityDuration = TimeSpan.FromMilliseconds(120);
    private static readonly TimeSpan _appearScaleDuration = TimeSpan.FromMilliseconds(160);
    private static readonly TimeSpan _spreadDuration = TimeSpan.FromMilliseconds(300);
    private static readonly TimeSpan _collapseDuration = TimeSpan.FromMilliseconds(250);
    private static readonly TimeSpan _disappearOpacityDuration = TimeSpan.FromMilliseconds(120);
    private static readonly TimeSpan _disappearScaleDuration = TimeSpan.FromMilliseconds(140);
    private readonly Visual _islandVisual;
    private readonly Visual _contentVisual;
    private readonly RectangleClip _clip;
    private readonly CompositionEasingFunction _easing;
    private Storyboard? _widthAnimation;
    private bool _isVisible;
    private bool _isClosing;
    private long _animationVersion;
    private long _thumbnailVersion;

    public unsafe PopupWindow()
    {
        InitializeComponent();
        ElementCompositionPreview.SetIsTranslationEnabled(ContentRow, true);
        _islandVisual = ElementCompositionPreview.GetElementVisual(Island);
        _contentVisual = ElementCompositionPreview.GetElementVisual(ContentRow);
        var compositor = _islandVisual.Compositor;
        var radius = new Vector2(HeightDip / 2f);
        _clip = compositor.CreateRectangleClip(CollapsedLeftDip, 0, CollapsedRightDip, HeightDip, radius, radius, radius, radius);
        ElementCompositionPreview.GetElementVisual(IslandForeground).Clip = _clip;
        _islandVisual.CenterPoint = new Vector3(WidthDip / 2f, HeightDip / 2f, 0);
        _easing = compositor.CreateCubicBezierEasingFunction(new Vector2(0.2f, 0), new Vector2(0, 1));
        IslandBackdrop.SizeChanged += (_, args) => FollowBackdropWidth(args.NewSize.Width);
        if (DesktopAcrylicController.IsSupported())
        {
            IslandBackdrop.SystemBackdrop = new PopupAcrylicBackdrop();
        }
        else
        {
            SolidFallback.Visibility = Visibility.Visible;
        }

        AlbumArtBrush.ImageFailed += (_, args) =>
        {
            Debug.WriteLine(args.ErrorMessage);
            ShowNoteArt();
        };

        // Create() keeps WS_DLGFRAME even without a border, which takes 3 pixels off each side of the client area.
        var presenter = OverlappedPresenter.CreateForContextMenu();
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

        var preference = DWM_WINDOW_CORNER_PREFERENCE.DWMWCP_DONOTROUND;
        PInvoke.DwmSetWindowAttribute(hwnd, DWMWINDOWATTRIBUTE.DWMWA_WINDOW_CORNER_PREFERENCE, &preference, sizeof(DWM_WINDOW_CORNER_PREFERENCE));
        SystemBackdrop = new TransparentBackdrop();
    }

    public void ShowTrack(MediaSnapshot track, IRandomAccessStreamReference? thumbnail, PopupPosition position, int sizePercent)
    {
        TitleText.Text = track.Title;
        ArtistText.Text = track.Artist;

        // The Viewbox shrinks text along with the popup, so its layout size grows to stay readable on screen.
        double fontSize = Math.Max(BodyFontSizeDip, MinVisibleFontSizeDip * 100 / sizePercent);
        TitleText.FontSize = fontSize;
        ArtistText.FontSize = fontSize;
        ShowNoteArt();

        var display = DisplayArea.Primary;
        var workArea = display.WorkArea;
        var monitor = Win32Interop.GetMonitorFromDisplayId(display.DisplayId);
        var result = PInvoke.GetDpiForMonitor(new HMONITOR(monitor), MONITOR_DPI_TYPE.MDT_EFFECTIVE_DPI, out uint dpiX, out _);
        double dpiScale = result.Failed ? 1.0 : dpiX / 96.0;
        double sizeScale = dpiScale * sizePercent / 100.0;

        // The Viewbox in the XAML fits the 360x80 layout to this size, so the animations stay in layout units.
        int width = (int)Math.Round(WidthDip * sizeScale);
        int height = (int)Math.Round(HeightDip * sizeScale);
        int margin = (int)Math.Round(MarginDip * dpiScale);
        var bounds = PopupPlacement.Compute(position, new PixelRect(workArea.X, workArea.Y, workArea.Width, workArea.Height), width, height, margin);

        if (!_isVisible)
        {
            AppWindow.Move(new PointInt32(workArea.X, workArea.Y));
        }

        AppWindow.MoveAndResize(new RectInt32(bounds.X, bounds.Y, bounds.Width, bounds.Height));
        if (!_isVisible)
        {
            _isVisible = true;
            FollowBackdropWidth(HeightDip);
            _islandVisual.Opacity = 0;
            _islandVisual.Scale = new Vector3(HiddenScale, HiddenScale, 1);
            AppWindow.Show(false);
            StartOpenAnimation(HeightDip, _appearScaleDuration);
        }
        else if (_isClosing)
        {
            StartOpenAnimation(IslandBackdrop.ActualWidth, TimeSpan.Zero);
        }

        _ = LoadThumbnailAsync(thumbnail);
    }

    public void UpdateThumbnail(IRandomAccessStreamReference? thumbnail)
    {
        _ = LoadThumbnailAsync(thumbnail);
    }

    public void HidePopup()
    {
        if (!_isVisible || _isClosing)
        {
            return;
        }

        _isClosing = true;
        var version = ++_animationVersion;
        var batch = _islandVisual.Compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
        AnimateBackdropWidth(IslandBackdrop.ActualWidth, HeightDip, _collapseDuration, TimeSpan.Zero);
        AnimateOpacity(0, _disappearOpacityDuration, _collapseDuration);
        AnimateScale(HiddenScale, _disappearScaleDuration, _collapseDuration);
        batch.End();
        batch.Completed += (_, _) =>
        {
            if (version == _animationVersion)
            {
                AppWindow.Hide();
                _isVisible = false;
                _isClosing = false;
            }
        };
    }

    // Composition drops a rounded clip on the acrylic and on its ancestors, so the round shape comes from the acrylic's own
    // size and corner radius. Its width is layout, so the clip and the content follow it to stay on the same frame.
    private void AnimateBackdropWidth(double from, double to, TimeSpan duration, TimeSpan delay)
    {
        _widthAnimation?.Stop();
        IslandBackdrop.Width = from;
        var frames = new DoubleAnimationUsingKeyFrames { EnableDependentAnimation = true, BeginTime = delay };
        frames.KeyFrames.Add(new SplineDoubleKeyFrame
        {
            KeyTime = KeyTime.FromTimeSpan(duration),
            Value = to,
            KeySpline = new KeySpline { ControlPoint1 = new Point(0.2, 0), ControlPoint2 = new Point(0, 1) },
        });
        Storyboard.SetTarget(frames, IslandBackdrop);
        Storyboard.SetTargetProperty(frames, "Width");
        _widthAnimation = new Storyboard();
        _widthAnimation.Children.Add(frames);
        _widthAnimation.Begin();
    }

    private void FollowBackdropWidth(double width)
    {
        float left = (WidthDip - (float)width) / 2;
        _clip.Left = left;
        _clip.Right = WidthDip - left;
        _contentVisual.Properties.InsertVector3("Translation", new Vector3(left, 0, 0));
    }

    private void AnimateOpacity(float to, TimeSpan duration, TimeSpan delay)
    {
        var animation = _islandVisual.Compositor.CreateScalarKeyFrameAnimation();
        animation.Duration = duration;
        animation.DelayTime = delay;
        animation.DelayBehavior = AnimationDelayBehavior.SetInitialValueBeforeDelay;
        animation.InsertExpressionKeyFrame(0, "this.StartingValue");
        animation.InsertKeyFrame(1, to, _easing);
        _islandVisual.StartAnimation("Opacity", animation);
    }

    private void AnimateScale(float to, TimeSpan duration, TimeSpan delay)
    {
        var animation = _islandVisual.Compositor.CreateVector3KeyFrameAnimation();
        animation.Duration = duration;
        animation.DelayTime = delay;
        animation.DelayBehavior = AnimationDelayBehavior.SetInitialValueBeforeDelay;
        animation.InsertExpressionKeyFrame(0, "this.StartingValue");
        animation.InsertKeyFrame(1, new Vector3(to, to, 1), _easing);
        _islandVisual.StartAnimation("Scale", animation);
    }

    private void StartOpenAnimation(double fromWidth, TimeSpan spreadDelay)
    {
        _isClosing = false;
        _animationVersion++;
        AnimateOpacity(1, _appearOpacityDuration, TimeSpan.Zero);
        AnimateScale(1, _appearScaleDuration, TimeSpan.Zero);
        AnimateBackdropWidth(fromWidth, WidthDip, _spreadDuration, spreadDelay);
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
