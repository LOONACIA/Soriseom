using Xunit;

namespace Soriseom.Core.Tests;

public class PopupDeciderTests
{
    private static DateTimeOffset Start { get; } = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void FirstTrackIsRecordedWithoutShowing(bool isPlaying)
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var track = new MediaSnapshot("player", "Song", "Artist", isPlaying);

        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(track, settings, isFullscreen: false, Start));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(track with { }, settings, isFullscreen: false, Start + PopupDecider.SettleDelay));

        var playing = track with { IsPlaying = true };
        var resumedAt = Start.AddSeconds(1);
        decider.Decide(playing, settings, isFullscreen: false, resumedAt);
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(playing, settings, isFullscreen: false, resumedAt + PopupDecider.SettleDelay));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void ChangedPlayingTrackShowsOnlyAfterSettling(bool startsWithSession)
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var original = new MediaSnapshot("player", "Original", "Artist", true);
        var track = original with { Title = "Next" };
        decider.Decide(startsWithSession ? original : null, settings, isFullscreen: false, Start);
        var changedAt = Start.AddSeconds(1);
        var settledAt = changedAt + PopupDecider.SettleDelay;

        Assert.Equal(new(PopupAction.None, null, settledAt), decider.Decide(track, settings, isFullscreen: false, changedAt));
        Assert.Equal(new(PopupAction.None, null, settledAt), decider.Decide(track with { }, settings, isFullscreen: false, settledAt.AddTicks(-1)));
        Assert.Equal(new(PopupAction.Show, track, null), decider.Decide(track with { }, settings, isFullscreen: false, settledAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(track, settings, isFullscreen: false, settledAt.AddSeconds(1)));
    }

    [Fact]
    public void SplitMetadataUpdatesRestartSettlingAndShowFinalTrackOnce()
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var original = new MediaSnapshot("browser", "Original", "Original artist", true);
        decider.Decide(original, settings, isFullscreen: false, Start);
        var titleOnly = original with { Title = "Next" };
        var final = titleOnly with { Artist = "Next artist" };
        var titleChangedAt = Start.AddSeconds(1);
        var artistChangedAt = titleChangedAt + (PopupDecider.SettleDelay / 2);
        var settledAt = artistChangedAt + PopupDecider.SettleDelay;

        Assert.Equal(new(PopupAction.None, null, titleChangedAt + PopupDecider.SettleDelay), decider.Decide(titleOnly, settings, isFullscreen: false, titleChangedAt));
        Assert.Equal(new(PopupAction.None, null, settledAt), decider.Decide(final, settings, isFullscreen: false, artistChangedAt));
        Assert.Equal(new(PopupAction.None, null, settledAt), decider.Decide(final, settings, isFullscreen: false, titleChangedAt + PopupDecider.SettleDelay));
        Assert.Equal(new(PopupAction.Show, final, null), decider.Decide(final, settings, isFullscreen: false, settledAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(final, settings, isFullscreen: false, settledAt.AddSeconds(1)));
    }

    [Theory]
    [InlineData(4, -1, PopupAction.Replace)]
    [InlineData(4, 0, PopupAction.Show)]
    [InlineData(4, 1, PopupAction.Show)]
    [InlineData(7, -1, PopupAction.Replace)]
    [InlineData(7, 0, PopupAction.Show)]
    [InlineData(7, 1, PopupAction.Show)]
    public void NextTrackUsesConfiguredDisplayDeadline(int displaySeconds, int offsetSeconds, PopupAction expectedAction)
    {
        var decider = new PopupDecider();
        var settings = new AppSettings { DisplaySeconds = displaySeconds };
        decider.Decide(null, settings, isFullscreen: false, Start);
        var first = new MediaSnapshot("player", "First", "Artist", true);
        var shownAt = Start.AddSeconds(1) + PopupDecider.SettleDelay;
        decider.Decide(first, settings, isFullscreen: false, shownAt - PopupDecider.SettleDelay);
        Assert.Equal(new(PopupAction.Show, first, null), decider.Decide(first, settings, isFullscreen: false, shownAt));
        var next = first with { Title = "Next" };
        var nextSettledAt = shownAt.AddSeconds(displaySeconds + offsetSeconds);

        Assert.Equal(new(PopupAction.None, null, nextSettledAt), decider.Decide(next, settings, isFullscreen: false, nextSettledAt - PopupDecider.SettleDelay));
        Assert.Equal(new(expectedAction, next, null), decider.Decide(next, settings, isFullscreen: false, nextSettledAt));
    }

    [Fact]
    public void ReplacementRestartsDisplayDurationUsingCurrentSettings()
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        decider.Decide(null, settings, isFullscreen: false, Start);
        var first = new MediaSnapshot("player", "First", "Artist", true);
        var shownAt = Start.AddSeconds(1) + PopupDecider.SettleDelay;
        decider.Decide(first, settings, isFullscreen: false, shownAt - PopupDecider.SettleDelay);
        Assert.Equal(new(PopupAction.Show, first, null), decider.Decide(first, settings, isFullscreen: false, shownAt));
        var second = first with { Title = "Second" };
        var replacedAt = shownAt.AddSeconds(3);
        var updatedSettings = settings with { DisplaySeconds = 7 };
        decider.Decide(second, updatedSettings, isFullscreen: false, replacedAt - PopupDecider.SettleDelay);
        Assert.Equal(new(PopupAction.Replace, second, null), decider.Decide(second, updatedSettings, isFullscreen: false, replacedAt));
        var third = first with { Title = "Third" };
        var thirdSettledAt = replacedAt.AddSeconds(6);

        decider.Decide(third, updatedSettings, isFullscreen: false, thirdSettledAt - PopupDecider.SettleDelay);
        Assert.Equal(new(PopupAction.Replace, third, null), decider.Decide(third, updatedSettings, isFullscreen: false, thirdSettledAt));
    }

    [Theory]
    [InlineData("other", true)]
    [InlineData("player", false)]
    [InlineData("other", false)]
    public void AppAndPlaybackChangesDoNotShowTheSameTrack(string appId, bool isPlaying)
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var original = new MediaSnapshot("player", "Song", "Artist", true);
        decider.Decide(original, settings, isFullscreen: false, Start);
        var changed = original with { AppId = appId, IsPlaying = isPlaying };
        var changedAt = Start.AddSeconds(1);

        Assert.Equal(new(PopupAction.None, null, changedAt + PopupDecider.SettleDelay), decider.Decide(changed, settings, isFullscreen: false, changedAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(changed, settings, isFullscreen: false, changedAt + PopupDecider.SettleDelay));
    }

    [Fact]
    public void TrackChangedWhilePausedShowsAfterPlaybackStartsAndSettles()
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var original = new MediaSnapshot("player", "Original", "Artist", true);
        decider.Decide(original, settings, isFullscreen: false, Start);
        var paused = original with { Title = "Next", IsPlaying = false };
        var changedAt = Start.AddSeconds(1);

        Assert.Equal(new(PopupAction.None, null, changedAt + PopupDecider.SettleDelay), decider.Decide(paused, settings, isFullscreen: false, changedAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(paused, settings, isFullscreen: false, changedAt + PopupDecider.SettleDelay));
        var playing = paused with { IsPlaying = true };
        var resumedAt = Start.AddSeconds(2);
        Assert.Equal(new(PopupAction.None, null, resumedAt + PopupDecider.SettleDelay), decider.Decide(playing, settings, isFullscreen: false, resumedAt));
        Assert.Equal(new(PopupAction.Show, playing, null), decider.Decide(playing, settings, isFullscreen: false, resumedAt + PopupDecider.SettleDelay));
    }

    [Fact]
    public void ResumingTheSameTrackDoesNotShowItAgain()
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var playing = new MediaSnapshot("player", "Song", "Artist", true);
        decider.Decide(playing, settings, isFullscreen: false, Start);
        var paused = playing with { IsPlaying = false };
        var pausedAt = Start.AddSeconds(1);
        decider.Decide(paused, settings, isFullscreen: false, pausedAt);
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(paused, settings, isFullscreen: false, pausedAt + PopupDecider.SettleDelay));
        var resumedAt = Start.AddSeconds(2);

        Assert.Equal(new(PopupAction.None, null, resumedAt + PopupDecider.SettleDelay), decider.Decide(playing, settings, isFullscreen: false, resumedAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(playing, settings, isFullscreen: false, resumedAt + PopupDecider.SettleDelay));
    }

    [Theory]
    [InlineData("Original", PopupAction.None)]
    [InlineData("Next", PopupAction.Show)]
    public void SessionDisappearancePreservesTheProcessedTrack(string returningTitle, PopupAction expectedAction)
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var original = new MediaSnapshot("player", "Original", "Artist", true);
        decider.Decide(original, settings, isFullscreen: false, Start);
        var disappearedAt = Start.AddSeconds(1);

        Assert.Equal(new(PopupAction.None, null, disappearedAt + PopupDecider.SettleDelay), decider.Decide(null, settings, isFullscreen: false, disappearedAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(null, settings, isFullscreen: false, disappearedAt + PopupDecider.SettleDelay));
        var returning = original with { Title = returningTitle };
        var returnedAt = Start.AddSeconds(2);
        Assert.Equal(new(PopupAction.None, null, returnedAt + PopupDecider.SettleDelay), decider.Decide(returning, settings, isFullscreen: false, returnedAt));
        Assert.Equal(new(expectedAction, expectedAction == PopupAction.None ? null : returning, null), decider.Decide(returning, settings, isFullscreen: false, returnedAt + PopupDecider.SettleDelay));
    }

    [Theory]
    [InlineData("")]
    [InlineData(" \t ")]
    public void BlankTitleDoesNotShowOrReplaceTheProcessedTrack(string title)
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var original = new MediaSnapshot("player", "Original", "Artist", true);
        decider.Decide(original, settings, isFullscreen: false, Start);
        var blank = original with { Title = title };
        var changedAt = Start.AddSeconds(1);

        Assert.Equal(new(PopupAction.None, null, changedAt + PopupDecider.SettleDelay), decider.Decide(blank, settings, isFullscreen: false, changedAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(blank, settings, isFullscreen: false, changedAt + PopupDecider.SettleDelay));
        var returnedAt = Start.AddSeconds(2);
        decider.Decide(original, settings, isFullscreen: false, returnedAt);
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(original, settings, isFullscreen: false, returnedAt + PopupDecider.SettleDelay));
        var next = original with { Title = "Next" };
        var nextAt = Start.AddSeconds(3);
        decider.Decide(next, settings, isFullscreen: false, nextAt);
        Assert.Equal(new(PopupAction.Show, next, null), decider.Decide(next, settings, isFullscreen: false, nextAt + PopupDecider.SettleDelay));
    }

    [Fact]
    public void DisabledAppTrackStaysSuppressedAfterReenablingButNextTrackShows()
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var disabledSettings = settings with { Apps = settings.Apps.Add("player", false) };
        decider.Decide(null, disabledSettings, isFullscreen: false, Start);
        var track = new MediaSnapshot("player", "Song", "Artist", true);
        var changedAt = Start.AddSeconds(1);
        var settledAt = changedAt + PopupDecider.SettleDelay;

        Assert.Equal(new(PopupAction.None, null, settledAt), decider.Decide(track, disabledSettings, isFullscreen: false, changedAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(track, disabledSettings, isFullscreen: false, settledAt));
        var enabledSettings = disabledSettings with { Apps = disabledSettings.Apps.SetItem("player", true) };
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(track, enabledSettings, isFullscreen: false, settledAt.AddSeconds(1)));
        var next = track with { Title = "Next" };
        var nextAt = settledAt.AddSeconds(2);
        decider.Decide(next, enabledSettings, isFullscreen: false, nextAt);
        Assert.Equal(new(PopupAction.Show, next, null), decider.Decide(next, enabledSettings, isFullscreen: false, nextAt + PopupDecider.SettleDelay));
    }

    [Fact]
    public void UnlistedAppTrackShows()
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        settings = settings with { Apps = settings.Apps.Add("disabled-player", false) };
        decider.Decide(null, settings, isFullscreen: false, Start);
        var track = new MediaSnapshot("new-player", "Song", "Artist", true);
        var changedAt = Start.AddSeconds(1);

        decider.Decide(track, settings, isFullscreen: false, changedAt);
        Assert.Equal(new(PopupAction.Show, track, null), decider.Decide(track, settings, isFullscreen: false, changedAt + PopupDecider.SettleDelay));
    }

    [Fact]
    public void FullscreenTrackStaysSuppressedAfterLeavingFullscreenButNextTrackShows()
    {
        var decider = new PopupDecider();
        var settings = new AppSettings { HideWhenFullscreen = true };
        decider.Decide(null, settings, isFullscreen: true, Start);
        var track = new MediaSnapshot("player", "Song", "Artist", true);
        var changedAt = Start.AddSeconds(1);
        var settledAt = changedAt + PopupDecider.SettleDelay;

        Assert.Equal(new(PopupAction.None, null, settledAt), decider.Decide(track, settings, isFullscreen: true, changedAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(track, settings, isFullscreen: true, settledAt));
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(track, settings, isFullscreen: false, settledAt.AddSeconds(1)));
        var next = track with { Title = "Next" };
        var nextAt = settledAt.AddSeconds(2);
        decider.Decide(next, settings, isFullscreen: false, nextAt);
        Assert.Equal(new(PopupAction.Show, next, null), decider.Decide(next, settings, isFullscreen: false, nextAt + PopupDecider.SettleDelay));
    }

    [Fact]
    public void FullscreenTrackShowsWhenHidingIsDisabled()
    {
        var decider = new PopupDecider();
        var settings = new AppSettings { HideWhenFullscreen = false };
        decider.Decide(null, settings, isFullscreen: true, Start);
        var track = new MediaSnapshot("player", "Song", "Artist", true);
        var changedAt = Start.AddSeconds(1);

        decider.Decide(track, settings, isFullscreen: true, changedAt);
        Assert.Equal(new(PopupAction.Show, track, null), decider.Decide(track, settings, isFullscreen: true, changedAt + PopupDecider.SettleDelay));
    }

    [Theory]
    [InlineData(false, -1, PopupAction.Replace)]
    [InlineData(false, 0, PopupAction.Show)]
    [InlineData(false, 1, PopupAction.Show)]
    [InlineData(true, -1, PopupAction.Replace)]
    [InlineData(true, 0, PopupAction.Show)]
    [InlineData(true, 1, PopupAction.Show)]
    public void SuppressedTrackPreservesDisplayDeadline(bool isFullscreen, int offsetSeconds, PopupAction expectedAction)
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        decider.Decide(null, settings, isFullscreen: false, Start);
        var first = new MediaSnapshot("player", "First", "Artist", true);
        var shownAt = Start.AddSeconds(1) + PopupDecider.SettleDelay;
        decider.Decide(first, settings, isFullscreen: false, shownAt - PopupDecider.SettleDelay);
        Assert.Equal(new(PopupAction.Show, first, null), decider.Decide(first, settings, isFullscreen: false, shownAt));
        var suppressed = first with { Title = "Suppressed" };
        var suppressedSettings = isFullscreen ? settings : settings with { Apps = settings.Apps.Add("player", false) };
        var suppressedAt = shownAt.AddSeconds(2);
        decider.Decide(suppressed, suppressedSettings, isFullscreen, suppressedAt - PopupDecider.SettleDelay);
        Assert.Equal(new(PopupAction.None, null, null), decider.Decide(suppressed, suppressedSettings, isFullscreen, suppressedAt));
        var next = first with { Title = "Next" };
        var nextSettledAt = shownAt.AddSeconds(settings.DisplaySeconds + offsetSeconds);

        decider.Decide(next, settings, isFullscreen: false, nextSettledAt - PopupDecider.SettleDelay);
        Assert.Equal(new(expectedAction, next, null), decider.Decide(next, settings, isFullscreen: false, nextSettledAt));
    }

    [Theory]
    [InlineData("song", "Artist")]
    [InlineData("Song", "artist")]
    [InlineData("Song", "Other artist")]
    [InlineData("Song ", "Artist")]
    public void TrackIdentityUsesOrdinalTitleAndArtist(string title, string artist)
    {
        var decider = new PopupDecider();
        var settings = new AppSettings();
        var original = new MediaSnapshot("player", "Song", "Artist", true);
        decider.Decide(original, settings, isFullscreen: false, Start);
        var changed = original with { Title = title, Artist = artist };
        var changedAt = Start.AddSeconds(1);

        decider.Decide(changed, settings, isFullscreen: false, changedAt);
        Assert.Equal(new(PopupAction.Show, changed, null), decider.Decide(changed, settings, isFullscreen: false, changedAt + PopupDecider.SettleDelay));
    }
}
