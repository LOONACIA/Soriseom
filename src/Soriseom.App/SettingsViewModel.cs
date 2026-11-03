using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using Soriseom.Core;
using Windows.ApplicationModel;

namespace Soriseom.App;

public sealed partial class SettingsViewModel : ObservableObject
{
    private readonly SettingsStore _store;
    private bool _isApplyingStartupState;

    internal SettingsViewModel(SettingsStore store)
    {
        _store = store;
        DisplaySeconds = store.Current.DisplaySeconds;
        PositionIndex = (int)store.Current.Position;
        HideWhenFullscreen = store.Current.HideWhenFullscreen;
        foreach (var (appId, enabled) in store.Current.Apps.OrderBy(app => app.Key, StringComparer.OrdinalIgnoreCase))
        {
            Apps.Add(new AppToggleViewModel(appId, enabled, OnAppEnabledChanged));
        }

        store.Changed += OnSettingsChanged;
    }

    public ObservableCollection<AppToggleViewModel> Apps { get; } = [];

    public int MinDisplaySeconds => AppSettings.MinDisplaySeconds;

    public int MaxDisplaySeconds => AppSettings.MaxDisplaySeconds;

    [ObservableProperty]
    public partial double DisplaySeconds { get; set; }

    [ObservableProperty]
    public partial int PositionIndex { get; set; }

    [ObservableProperty]
    public partial bool HideWhenFullscreen { get; set; }

    [ObservableProperty]
    public partial bool LaunchAtStartup { get; set; }

    [ObservableProperty]
    public partial bool CanChangeLaunchAtStartup { get; set; }

    [ObservableProperty]
    public partial bool ShowStartupNotice { get; set; }

    public async Task RefreshLaunchAtStartupAsync()
    {
        ApplyStartupState(await StartupRegistration.GetStateAsync());
    }

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

    partial void OnLaunchAtStartupChanged(bool value)
    {
        if (_isApplyingStartupState)
        {
            return;
        }

        _ = SetLaunchAtStartupAsync(value);
    }

    private void ApplyStartupState(StartupTaskState? state)
    {
        _isApplyingStartupState = true;
        LaunchAtStartup = state is StartupTaskState.Enabled or StartupTaskState.EnabledByPolicy;
        CanChangeLaunchAtStartup = state is StartupTaskState.Enabled or StartupTaskState.Disabled;
        ShowStartupNotice = !CanChangeLaunchAtStartup;
        _isApplyingStartupState = false;
    }

    private async Task SetLaunchAtStartupAsync(bool enabled)
    {
        ApplyStartupState(await StartupRegistration.SetEnabledAsync(enabled));
    }

    private void OnSettingsChanged(object? sender, EventArgs e)
    {
        foreach (var (appId, enabled) in _store.Current.Apps)
        {
            if (Apps.Any(app => string.Equals(app.AppId, appId, StringComparison.Ordinal)))
            {
                continue;
            }

            var index = 0;
            while (index < Apps.Count && StringComparer.OrdinalIgnoreCase.Compare(Apps[index].AppId, appId) < 0)
            {
                index++;
            }

            Apps.Insert(index, new AppToggleViewModel(appId, enabled, OnAppEnabledChanged));
        }
    }

    private void OnAppEnabledChanged(string appId, bool enabled)
    {
        _store.Update(_store.Current with { Apps = _store.Current.Apps.SetItem(appId, enabled) });
    }
}
