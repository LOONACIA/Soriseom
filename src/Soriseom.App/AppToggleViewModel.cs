using CommunityToolkit.Mvvm.ComponentModel;

namespace Soriseom.App;

public sealed partial class AppToggleViewModel : ObservableObject
{
    private readonly Action<string, bool> _enabledChanged;

    internal AppToggleViewModel(string appId, string displayName, bool isEnabled, Action<string, bool> enabledChanged)
    {
        _enabledChanged = enabledChanged;
        AppId = appId;
        DisplayName = displayName;
        IsEnabled = isEnabled;
    }

    public string AppId { get; }

    public string DisplayName { get; }

    [ObservableProperty]
    public partial bool IsEnabled { get; set; }

    partial void OnIsEnabledChanged(bool value)
    {
        _enabledChanged(AppId, value);
    }
}
