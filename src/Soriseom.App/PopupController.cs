using Microsoft.UI.Dispatching;
using Soriseom.Core;

namespace Soriseom.App;

internal sealed class PopupController
{
    private readonly MediaSessionAdapter _adapter;
    private readonly PopupDecider _decider;
    private readonly PopupWindow _window;
    private readonly AppSettings _settings;
    private readonly DispatcherQueueTimer _reevaluateTimer;
    private readonly DispatcherQueueTimer _hideTimer;

    public PopupController(DispatcherQueue dispatcherQueue)
    {
        _adapter = new MediaSessionAdapter(dispatcherQueue);
        _decider = new PopupDecider();
        _window = new PopupWindow();
        _settings = new AppSettings();
        _reevaluateTimer = dispatcherQueue.CreateTimer();
        _reevaluateTimer.IsRepeating = false;
        _reevaluateTimer.Tick += (_, _) => Evaluate();
        _hideTimer = dispatcherQueue.CreateTimer();
        _hideTimer.IsRepeating = false;
        _hideTimer.Tick += (_, _) => _window.HidePopup();
    }

    public async Task StartAsync()
    {
        await _adapter.StartAsync();
        _adapter.Changed += (_, _) => Evaluate();
        Evaluate();
    }

    private void Evaluate()
    {
        var now = DateTimeOffset.UtcNow;
        var decision = _decider.Decide(_adapter.Current, _settings, isFullscreen: false, now);
        _reevaluateTimer.Stop();
        if (decision.ReevaluateAt is { } reevaluateAt)
        {
            var interval = reevaluateAt - now;
            _reevaluateTimer.Interval = interval < TimeSpan.Zero ? TimeSpan.Zero : interval;
            _reevaluateTimer.Start();
        }

        if (decision.Action is PopupAction.Show or PopupAction.Replace && decision.Track is { } track)
        {
            _window.ShowTrack(track, _settings.Position);
            _hideTimer.Stop();
            _hideTimer.Interval = TimeSpan.FromSeconds(_settings.DisplaySeconds);
            _hideTimer.Start();
        }
    }
}
