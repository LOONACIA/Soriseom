using CommunityToolkit.Mvvm.ComponentModel;
using Soriseom.Core;

namespace Soriseom.App;

public sealed partial class SettingsViewModel : ObservableObject
{
    private readonly SettingsStore _store;

    internal SettingsViewModel(SettingsStore store)
    {
        _store = store;
        DisplaySeconds = store.Current.DisplaySeconds;
        PositionIndex = (int)store.Current.Position;
        HideWhenFullscreen = store.Current.HideWhenFullscreen;
    }

    public int MinDisplaySeconds => AppSettings.MinDisplaySeconds;

    public int MaxDisplaySeconds => AppSettings.MaxDisplaySeconds;

    [ObservableProperty]
    public partial double DisplaySeconds { get; set; }

    [ObservableProperty]
    public partial int PositionIndex { get; set; }

    [ObservableProperty]
    public partial bool HideWhenFullscreen { get; set; }

    partial void OnDisplaySecondsChanged(double value)
    {
        _store.Update(_store.Current with { DisplaySeconds = (int)Math.Round(value) });
    }

    partial void OnPositionIndexChanged(int value)
    {
        var position = (PopupPosition)value;
        if (Enum.IsDefined(position))
        {
            _store.Update(_store.Current with { Position = position });
        }
    }

    partial void OnHideWhenFullscreenChanged(bool value)
    {
        _store.Update(_store.Current with { HideWhenFullscreen = value });
    }
}
