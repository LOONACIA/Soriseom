using System.Collections.Immutable;
using System.Diagnostics;
using Soriseom.Core;
using Windows.Storage;

namespace Soriseom.App;

internal sealed class SettingsStore
{
    private const string DisplaySecondsKey = "DisplaySeconds";
    private const string PositionKey = "Position";
    private const string HideWhenFullscreenKey = "HideWhenFullscreen";
    private const string AppsContainerName = "Apps";

    public SettingsStore()
    {
        Current = Load();
    }

    public event EventHandler? Changed;

    public AppSettings Current { get; private set; }

    public void Update(AppSettings settings)
    {
        if (settings == Current)
        {
            return;
        }

        Current = settings;
        try
        {
            var values = ApplicationData.Current.LocalSettings.Values;
            values[DisplaySecondsKey] = settings.DisplaySeconds;
            values[PositionKey] = settings.Position.ToString();
            values[HideWhenFullscreenKey] = settings.HideWhenFullscreen;
            var appsValues = ApplicationData.Current.LocalSettings.CreateContainer(AppsContainerName, ApplicationDataCreateDisposition.Always).Values;
            foreach (var (appId, enabled) in settings.Apps)
            {
                appsValues[appId] = enabled;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine(ex);
        }

        Changed?.Invoke(this, EventArgs.Empty);
    }

    private static AppSettings Load()
    {
        try
        {
            var settings = new AppSettings();
            var values = ApplicationData.Current.LocalSettings.Values;
            if (values.TryGetValue(DisplaySecondsKey, out var displayValue) && displayValue is int displaySeconds)
            {
                settings = settings with { DisplaySeconds = displaySeconds };
            }

            if (values.TryGetValue(PositionKey, out var positionValue) && positionValue is string text
                && Enum.TryParse(text, out PopupPosition position) && Enum.IsDefined(position))
            {
                settings = settings with { Position = position };
            }

            if (values.TryGetValue(HideWhenFullscreenKey, out var fullscreenValue) && fullscreenValue is bool hideWhenFullscreen)
            {
                settings = settings with { HideWhenFullscreen = hideWhenFullscreen };
            }

            var apps = ImmutableDictionary<string, bool>.Empty;
            var appsValues = ApplicationData.Current.LocalSettings.CreateContainer(AppsContainerName, ApplicationDataCreateDisposition.Always).Values;
            foreach (var (appId, value) in appsValues)
            {
                if (value is bool enabled)
                {
                    apps = apps.Add(appId, enabled);
                }
            }

            return settings with { Apps = apps };
        }
        catch (Exception ex)
        {
            Debug.WriteLine(ex);
            return new AppSettings();
        }
    }
}
