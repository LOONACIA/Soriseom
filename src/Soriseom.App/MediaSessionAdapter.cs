using System.Diagnostics;
using Microsoft.UI.Dispatching;
using Soriseom.Core;
using Windows.Media.Control;
using Windows.Storage.Streams;

namespace Soriseom.App;

internal sealed class MediaSessionAdapter
{
    private readonly DispatcherQueue _dispatcherQueue;
    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private GlobalSystemMediaTransportControlsSession? _session;
    private long _readVersion;

    public MediaSessionAdapter(DispatcherQueue dispatcherQueue)
    {
        _dispatcherQueue = dispatcherQueue;
    }

    public event EventHandler? Changed;

    public MediaSnapshot? Current { get; private set; }

    public IRandomAccessStreamReference? CurrentThumbnail { get; private set; }

    public async Task StartAsync()
    {
        try
        {
            PopupTrace.Write("adapter request begin");
            _manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            PopupTrace.Write("adapter request end");
            _manager.CurrentSessionChanged += OnCurrentSessionChanged;
            await AttachCurrentSessionAsync();
            PopupTrace.Write("adapter start end");
        }
        catch (Exception exception)
        {
            PopupTrace.Failure("adapter start", exception);
            Debug.WriteLine(exception);
            Current = null;
        }
    }

    private void OnCurrentSessionChanged(GlobalSystemMediaTransportControlsSessionManager sender, CurrentSessionChangedEventArgs args)
    {
        bool queued = _dispatcherQueue.TryEnqueue(async () => await AttachCurrentSessionAsync());
        PopupTrace.Write($"event session queued={queued}");
    }

    private void OnMediaPropertiesChanged(GlobalSystemMediaTransportControlsSession sender, MediaPropertiesChangedEventArgs args)
    {
        bool queued = _dispatcherQueue.TryEnqueue(async () => await RefreshMediaPropertiesAsync());
        PopupTrace.Write($"event properties queued={queued}");
    }

    private void OnPlaybackInfoChanged(GlobalSystemMediaTransportControlsSession sender, PlaybackInfoChangedEventArgs args)
    {
        bool queued = _dispatcherQueue.TryEnqueue(RefreshPlaybackInfo);
        PopupTrace.Write($"event playback queued={queued}");
    }

    private async Task AttachCurrentSessionAsync()
    {
        try
        {
            if (_session is not null)
            {
                _session.MediaPropertiesChanged -= OnMediaPropertiesChanged;
                _session.PlaybackInfoChanged -= OnPlaybackInfoChanged;
            }

            _readVersion++;
            _session = _manager?.GetCurrentSession();
            PopupTrace.Write($"attach session={PopupTrace.Mask(_session?.SourceAppUserModelId)} version={_readVersion}");
            Current = null;
            if (_session is null)
            {
                CurrentThumbnail = null;
                Changed?.Invoke(this, EventArgs.Empty);
                return;
            }

            _session.MediaPropertiesChanged += OnMediaPropertiesChanged;
            _session.PlaybackInfoChanged += OnPlaybackInfoChanged;
            await RefreshMediaPropertiesAsync();
        }
        catch (Exception exception)
        {
            PopupTrace.Failure("attach", exception);
            Debug.WriteLine(exception);
        }
    }

    private async Task RefreshMediaPropertiesAsync()
    {
        var session = _session;
        if (session is null)
        {
            return;
        }

        var version = ++_readVersion;
        PopupTrace.Write($"read begin version={version}");
        try
        {
            var properties = await session.TryGetMediaPropertiesAsync();
            if (version != _readVersion || session != _session)
            {
                PopupTrace.Write($"read dropped version={version} latest={_readVersion} sameSession={session == _session}");
                return;
            }

            bool isPlaying = session.GetPlaybackInfo().PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            Current = new MediaSnapshot(session.SourceAppUserModelId, properties.Title ?? string.Empty, properties.Artist ?? string.Empty, isPlaying);
            CurrentThumbnail = properties.Thumbnail;
            PopupTrace.Write($"read end version={version} app={PopupTrace.Mask(session.SourceAppUserModelId)} title={PopupTrace.Mask(properties.Title)} artist={PopupTrace.Mask(properties.Artist)} playing={isPlaying} thumbnail={properties.Thumbnail is not null}");
            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception exception)
        {
            PopupTrace.Failure($"read version={version}", exception);
            Debug.WriteLine(exception);
        }
    }

    private void RefreshPlaybackInfo()
    {
        if (_session is not { } session || Current is not { } track)
        {
            PopupTrace.Write("playback skipped");
            return;
        }

        try
        {
            bool isPlaying = session.GetPlaybackInfo().PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            Current = new MediaSnapshot(session.SourceAppUserModelId, track.Title, track.Artist, isPlaying);
            PopupTrace.Write($"playback playing={isPlaying}");
            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception exception)
        {
            PopupTrace.Failure("playback", exception);
            Debug.WriteLine(exception);
        }
    }
}
