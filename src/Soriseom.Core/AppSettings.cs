using System.Collections.Immutable;

namespace Soriseom.Core;

public sealed record AppSettings
{
    public const int MinDisplaySeconds = 2;
    public const int MaxDisplaySeconds = 10;
    public const int DefaultDisplaySeconds = 4;

    public int DisplaySeconds
    {
        get;
        init => field = Math.Clamp(value, MinDisplaySeconds, MaxDisplaySeconds);
    } = DefaultDisplaySeconds;

    public PopupPosition Position { get; init; } = PopupPosition.TopCenter;

    public bool HideWhenFullscreen { get; init; } = true;

    public AppLanguage Language { get; init; } = AppLanguage.System;

    public bool LaunchAtStartup { get; init; } = true;

    public ImmutableDictionary<string, bool> Apps { get; init; } = ImmutableDictionary<string, bool>.Empty;

    public bool IsAppEnabled(string appId) => !Apps.TryGetValue(appId, out bool enabled) || enabled;

    public AppSettings WithAppSeen(string appId) => string.IsNullOrWhiteSpace(appId) || Apps.ContainsKey(appId)
        ? this
        : this with { Apps = Apps.Add(appId, true) };
}
