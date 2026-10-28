using Xunit;

namespace Soriseom.Core.Tests;

public class AppSettingsTests
{
    [Fact]
    public void DefaultsMatchSettingsSpecification()
    {
        var settings = new AppSettings();

        Assert.Equal(2, AppSettings.MinDisplaySeconds);
        Assert.Equal(10, AppSettings.MaxDisplaySeconds);
        Assert.Equal(4, AppSettings.DefaultDisplaySeconds);
        Assert.Equal(4, settings.DisplaySeconds);
        Assert.Equal(PopupPosition.TopCenter, settings.Position);
        Assert.True(settings.HideWhenFullscreen);
        Assert.Equal(AppLanguage.System, settings.Language);
        Assert.True(settings.LaunchAtStartup);
        Assert.Empty(settings.Apps);
    }

    [Theory]
    [InlineData(int.MinValue, 2)]
    [InlineData(0, 2)]
    [InlineData(1, 2)]
    [InlineData(2, 2)]
    [InlineData(4, 4)]
    [InlineData(10, 10)]
    [InlineData(11, 10)]
    [InlineData(int.MaxValue, 10)]
    public void DisplaySecondsClampsOnInitialization(int value, int expected)
    {
        var settings = new AppSettings { DisplaySeconds = value };

        Assert.Equal(expected, settings.DisplaySeconds);
    }

    [Theory]
    [InlineData(int.MinValue, 2)]
    [InlineData(0, 2)]
    [InlineData(1, 2)]
    [InlineData(2, 2)]
    [InlineData(4, 4)]
    [InlineData(10, 10)]
    [InlineData(11, 10)]
    [InlineData(int.MaxValue, 10)]
    public void DisplaySecondsClampsOnCopy(int value, int expected)
    {
        var original = new AppSettings();

        var updated = original with { DisplaySeconds = value };

        Assert.Equal(expected, updated.DisplaySeconds);
        Assert.Equal(4, original.DisplaySeconds);
    }

    [Fact]
    public void IsAppEnabledReturnsTrueForUnknownApp()
    {
        var settings = new AppSettings();

        Assert.True(settings.IsAppEnabled("unknown"));
        Assert.Empty(settings.Apps);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void IsAppEnabledReturnsStoredValue(bool enabled)
    {
        var settings = new AppSettings();
        settings = settings with { Apps = settings.Apps.Add("player", enabled) };

        Assert.Equal(enabled, settings.IsAppEnabled("player"));
    }

    [Fact]
    public void WithAppSeenAddsNewAppAsEnabledWithoutChangingOriginal()
    {
        var original = new AppSettings();

        var updated = original.WithAppSeen("player");

        Assert.NotSame(original, updated);
        Assert.Empty(original.Apps);
        Assert.Single(updated.Apps);
        Assert.True(updated.Apps["player"]);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void WithAppSeenPreservesExistingAppAndReturnsSameSettings(bool enabled)
    {
        var original = new AppSettings();
        original = original with { Apps = original.Apps.Add("player", enabled) };

        var updated = original.WithAppSeen("player");

        Assert.Same(original, updated);
        Assert.Equal(enabled, updated.Apps["player"]);
    }

    [Fact]
    public void AppIdsUseOrdinalCaseSensitiveComparison()
    {
        var settings = new AppSettings();
        settings = settings with { Apps = settings.Apps.Add("Player", false) };

        Assert.False(settings.IsAppEnabled("Player"));
        Assert.True(settings.IsAppEnabled("player"));

        var updated = settings.WithAppSeen("player");

        Assert.Equal(2, updated.Apps.Count);
        Assert.False(updated.Apps["Player"]);
        Assert.True(updated.Apps["player"]);
    }
}
