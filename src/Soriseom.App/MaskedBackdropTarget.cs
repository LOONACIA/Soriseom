using System.Runtime.Versioning;
using Microsoft.UI.Composition;

namespace Soriseom.App;

/// <summary>
/// Stands between DesktopAcrylicController and the real target, so every brush the controller sets, its flat color fallback included, gets the pill mask.
/// </summary>
[SupportedOSPlatform("windows10.0.18362.0")]
internal sealed partial class MaskedBackdropTarget : ICompositionSupportsSystemBackdrop
{
    private readonly ICompositionSupportsSystemBackdrop _target;
    private readonly PillAlphaMask _mask;
    private Windows.UI.Composition.CompositionBrush? _brush;

    public MaskedBackdropTarget(ICompositionSupportsSystemBackdrop target, PillAlphaMask mask)
    {
        _target = target;
        _mask = mask;
    }

    public Windows.UI.Composition.CompositionBrush? SystemBackdrop
    {
        get
        {
            return _brush;
        }

        set
        {
            _brush = value;
            _target.SystemBackdrop = value is null ? null : _mask.Apply(value);
        }
    }
}
