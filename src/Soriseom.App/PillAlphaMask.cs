using System.Numerics;
using System.Runtime.Versioning;
using Windows.UI;
using Windows.UI.Composition;

namespace Soriseom.App;

/// <summary>
/// Masks a brush to the popup's pill. The corner radius of SystemBackdropElement and shapes in a visual surface both leave a hard stair step edge, so the alpha fades out by gradient instead.
/// </summary>
[SupportedOSPlatform("windows10.0.18362.0")]
internal sealed class PillAlphaMask
{
    // Drawn at twice the layout size so the edge holds up on high DPI screens.
    private const float Scale = 2;
    private const float HeightDip = 80;
    private const float RadiusDip = HeightDip / 2;
    private const float FadeDip = 1.2f;
    private static readonly Color _opaque = Color.FromArgb(255, 255, 255, 255);
    private static readonly Color _clear = Color.FromArgb(0, 255, 255, 255);
    private ContainerVisual? _root;
    private SpriteVisual? _body;
    private SpriteVisual? _rightCap;
    private CompositionVisualSurface? _surface;
    private float _widthDip = HeightDip;

    public CompositionBrush Apply(CompositionBrush source)
    {
        var compositor = source.Compositor;
        if (_surface is null)
        {
            CreateVisuals(compositor);
        }

        var maskSurface = compositor.CreateSurfaceBrush(_surface);
        maskSurface.Stretch = CompositionStretch.Fill;
        var mask = compositor.CreateMaskBrush();
        mask.Source = source;
        mask.Mask = maskSurface;
        return mask;
    }

    public void SetWidth(float widthDip)
    {
        _widthDip = widthDip;
        if (_surface is null)
        {
            return;
        }

        var size = new Vector2(widthDip * Scale, HeightDip * Scale);
        _root!.Size = size;
        _body!.Size = new Vector2((widthDip - (2 * RadiusDip)) * Scale, HeightDip * Scale);
        _rightCap!.Offset = new Vector3((widthDip - RadiusDip) * Scale, 0, 0);
        _surface.SourceSize = size;
    }

    private static SpriteVisual CreateCap(Compositor compositor, Vector2 center)
    {
        var brush = compositor.CreateRadialGradientBrush();
        brush.EllipseCenter = center;
        brush.EllipseRadius = new Vector2(1, 0.5f);
        brush.ColorStops.Add(compositor.CreateColorGradientStop(1 - (FadeDip / RadiusDip), _opaque));
        brush.ColorStops.Add(compositor.CreateColorGradientStop(1, _clear));
        var cap = compositor.CreateSpriteVisual();
        cap.Brush = brush;
        cap.Size = new Vector2(RadiusDip * Scale, HeightDip * Scale);
        return cap;
    }

    private void CreateVisuals(Compositor compositor)
    {
        var body = compositor.CreateLinearGradientBrush();
        body.StartPoint = new Vector2(0, 0);
        body.EndPoint = new Vector2(0, 1);
        body.ColorStops.Add(compositor.CreateColorGradientStop(0, _clear));
        body.ColorStops.Add(compositor.CreateColorGradientStop(FadeDip / HeightDip, _opaque));
        body.ColorStops.Add(compositor.CreateColorGradientStop(1 - (FadeDip / HeightDip), _opaque));
        body.ColorStops.Add(compositor.CreateColorGradientStop(1, _clear));
        _body = compositor.CreateSpriteVisual();
        _body.Brush = body;
        _body.Offset = new Vector3(RadiusDip * Scale, 0, 0);
        _rightCap = CreateCap(compositor, new Vector2(0, 0.5f));
        _root = compositor.CreateContainerVisual();
        _root.Children.InsertAtTop(CreateCap(compositor, new Vector2(1, 0.5f)));
        _root.Children.InsertAtTop(_body);
        _root.Children.InsertAtTop(_rightCap);
        _surface = compositor.CreateVisualSurface();
        _surface.SourceVisual = _root;
        SetWidth(_widthDip);
    }
}
