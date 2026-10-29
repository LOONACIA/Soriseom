using System.Diagnostics;
using Microsoft.UI.Dispatching;
using Soriseom.Core;
using Windows.Storage.Streams;
using Windows.Win32;
using Windows.Win32.UI.Shell;

namespace Soriseom.App;

internal sealed class PopupController
{
    private readonly MediaSessionAdapter _adapter;
    private readonly PopupDecider _decider;
    private readonly PopupWindow _window;
    private readonly SettingsStore _store;
    private readonly DispatcherQueueTimer _reevaluateTimer;
    private readonly DispatcherQueueTimer _hideTimer;
    private MediaSnapshot? _displayedTrack;
    private IRandomAccessStreamReference? _displayedThumbnail;
    private bool _isShowing;

    public PopupController(DispatcherQueue dispatcherQueue, SettingsStore store)
    {
        _adapter = new MediaSessionAdapter(dispatcherQueue);
        _decider = new PopupDecider();
        _window = new PopupWindow();
        _store = store;
        _reevaluateTimer = dispatcherQueue.CreateTimer();
        _reevaluateTimer.IsRepeating = false;
        _reevaluateTimer.Tick += (_, _) => Evaluate();
        _hideTimer = dispatcherQueue.CreateTimer();
        _hideTimer.IsRepeating = false;
        _hideTimer.Tick += (_, _) =>
        {
            _isShowing = false;
            _window.HidePopup();
        };
    }

    public async Task StartAsync()
    {
        await _adapter.StartAsync();
        _adapter.Changed += (_, _) => Evaluate();
        Evaluate();
    }

    private static bool IsFullscreen()
    {
        var result = PInvoke.SHQueryUserNotificationState(out QUERY_USER_NOTIFICATION_STATE state);
        if (result.Succeeded)
        {
            return state is QUERY_USER_NOTIFICATION_STATE.QUNS_BUSY
                or QUERY_USER_NOTIFICATION_STATE.QUNS_RUNNING_D3D_FULL_SCREEN
                or QUERY_USER_NOTIFICATION_STATE.QUNS_PRESENTATION_MODE;
        }

        Debug.WriteLine($"SHQueryUserNotificationState failed: {result}");
        return false;
    }

    private void Evaluate()
    {
        var settings = _store.Current;
        var now = DateTimeOffset.UtcNow;
        var decision = _decider.Decide(_adapter.Current, settings, isFullscreen: IsFullscreen(), now);
        _reevaluateTimer.Stop();
        if (decision.ReevaluateAt is { } reevaluateAt)
        {
            var interval = reevaluateAt - now;
            _reevaluateTimer.Interval = interval < TimeSpan.Zero ? TimeSpan.Zero : interval;
            _reevaluateTimer.Start();
        }

        if (decision.Action is PopupAction.Show or PopupAction.Replace && decision.Track is { } track)
        {
            _displayedTrack = track;
            _displayedThumbnail = _adapter.CurrentThumbnail;
            _isShowing = true;
            _window.ShowTrack(track, _displayedThumbnail, settings.Position);
            _hideTimer.Stop();
            _hideTimer.Interval = TimeSpan.FromSeconds(settings.DisplaySeconds);
            _hideTimer.Start();
        }
        else if (decision.Action == PopupAction.None && _isShowing
            && _adapter.Current is { } current && _displayedTrack is { } displayed
            && string.Equals(current.Title, displayed.Title, StringComparison.Ordinal)
            && string.Equals(current.Artist, displayed.Artist, StringComparison.Ordinal)
            && !ReferenceEquals(_adapter.CurrentThumbnail, _displayedThumbnail))
        {
            _displayedThumbnail = _adapter.CurrentThumbnail;
            _window.UpdateThumbnail(_displayedThumbnail);
        }
    }
}
