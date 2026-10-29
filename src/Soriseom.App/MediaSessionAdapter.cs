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
            _manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            _manager.CurrentSessionChanged += OnCurrentSessionChanged;
            await AttachCurrentSessionAsync();
        }
        catch (Exception exception)
        {
            Debug.WriteLine(exception);
            Current = null;
        }
    }

    private void OnCurrentSessionChanged(GlobalSystemMediaTransportControlsSessionManager sender, CurrentSessionChangedEventArgs args)
    {
        _dispatcherQueue.TryEnqueue(async () => await AttachCurrentSessionAsync());
    }

    private void OnMediaPropertiesChanged(GlobalSystemMediaTransportControlsSession sender, MediaPropertiesChangedEventArgs args)
    {
        _dispatcherQueue.TryEnqueue(async () => await RefreshMediaPropertiesAsync());
    }

    private void OnPlaybackInfoChanged(GlobalSystemMediaTransportControlsSession sender, PlaybackInfoChangedEventArgs args)
    {
        _dispatcherQueue.TryEnqueue(RefreshPlaybackInfo);
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
        try
        {
            var properties = await session.TryGetMediaPropertiesAsync();
            if (version != _readVersion || session != _session)
            {
                return;
            }

            bool isPlaying = session.GetPlaybackInfo().PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            Current = new MediaSnapshot(session.SourceAppUserModelId, properties.Title ?? string.Empty, properties.Artist ?? string.Empty, isPlaying);
            CurrentThumbnail = properties.Thumbnail;
            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception exception)
        {
            Debug.WriteLine(exception);
        }
    }

    private void RefreshPlaybackInfo()
    {
        if (_session is not { } session || Current is not { } track)
        {
            return;
        }

        try
        {
            bool isPlaying = session.GetPlaybackInfo().PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            Current = new MediaSnapshot(session.SourceAppUserModelId, track.Title, track.Artist, isPlaying);
            Changed?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception exception)
        {
            Debug.WriteLine(exception);
        }
    }
}
