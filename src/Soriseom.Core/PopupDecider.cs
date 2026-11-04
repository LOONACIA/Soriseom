namespace Soriseom.Core;

public sealed class PopupDecider
{
    public static readonly TimeSpan SettleDelay = TimeSpan.FromMilliseconds(500);

    private bool _initialized;
    private MediaSnapshot? _lastSnapshot;
    private DateTimeOffset? _reevaluateAt;
    private string? _processedTitle;
    private string? _processedArtist;
    private DateTimeOffset? _displayUntil;

    public PopupDecision Decide(MediaSnapshot? snapshot, AppSettings settings, bool isFullscreen, DateTimeOffset now, bool isDoNotDisturb = false)
    {
        if (!_initialized)
        {
            _initialized = true;
            _lastSnapshot = snapshot;
            if (snapshot is not null && !string.IsNullOrWhiteSpace(snapshot.Title))
            {
                _processedTitle = snapshot.Title;
                _processedArtist = snapshot.Artist;
            }

            return new(PopupAction.None, null, null);
        }

        if (snapshot != _lastSnapshot)
        {
            _lastSnapshot = snapshot;
            _reevaluateAt = now + SettleDelay;
            return new(PopupAction.None, null, _reevaluateAt);
        }

        if (now < _reevaluateAt)
        {
            return new(PopupAction.None, null, _reevaluateAt);
        }

        _reevaluateAt = null;
        if (snapshot is null || !snapshot.IsPlaying || string.IsNullOrWhiteSpace(snapshot.Title))
        {
            return new(PopupAction.None, null, null);
        }

        if (string.Equals(snapshot.Title, _processedTitle, StringComparison.Ordinal)
            && string.Equals(snapshot.Artist, _processedArtist, StringComparison.Ordinal))
        {
            return new(PopupAction.None, null, null);
        }

        _processedTitle = snapshot.Title;
        _processedArtist = snapshot.Artist;

        // Windows can turn do not disturb on by itself for a full-screen app, so during full screen only the setting decides.
        var hiddenByEnvironment = isFullscreen ? settings.HideWhenFullscreen : isDoNotDisturb;
        if (!settings.IsAppEnabled(snapshot.AppId) || hiddenByEnvironment)
        {
            return new(PopupAction.None, null, null);
        }

        var action = now < _displayUntil ? PopupAction.Replace : PopupAction.Show;
        _displayUntil = now.AddSeconds(settings.DisplaySeconds);
        return new(action, snapshot, null);
    }
}
