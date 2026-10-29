using Xunit;

namespace Soriseom.Core.Tests;

public class PopupPlacementTests
{
    [Theory]
    [InlineData(PopupPosition.TopLeft, 16, 16)]
    [InlineData(PopupPosition.TopCenter, 780, 16)]
    [InlineData(PopupPosition.TopRight, 1544, 16)]
    [InlineData(PopupPosition.BottomLeft, 16, 944)]
    [InlineData(PopupPosition.BottomCenter, 780, 944)]
    [InlineData(PopupPosition.BottomRight, 1544, 944)]
    public void ComputePlacesPopupAtRequestedPosition(PopupPosition position, int expectedX, int expectedY)
    {
        var workArea = new PixelRect(0, 0, 1920, 1040);

        var result = PopupPlacement.Compute(position, workArea, 360, 80, 16);

        Assert.Equal(new PixelRect(expectedX, expectedY, 360, 80), result);
    }

    [Theory]
    [InlineData(PopupPosition.TopLeft, 76, 64)]
    [InlineData(PopupPosition.TopCenter, 810, 64)]
    [InlineData(PopupPosition.BottomRight, 1544, 984)]
    public void ComputeIncludesWorkAreaOffset(PopupPosition position, int expectedX, int expectedY)
    {
        var workArea = new PixelRect(60, 48, 1860, 1032);

        var result = PopupPlacement.Compute(position, workArea, 360, 80, 16);

        Assert.Equal(new PixelRect(expectedX, expectedY, 360, 80), result);
    }

    [Fact]
    public void ComputeCenterUsesIntegerDivisionForOddRemainingWidth()
    {
        var workArea = new PixelRect(0, 0, 1921, 1040);

        var result = PopupPlacement.Compute(PopupPosition.TopCenter, workArea, 360, 80, 16);

        Assert.Equal(780, result.X);
    }

    [Fact]
    public void ComputeRejectsUndefinedPosition()
    {
        var workArea = new PixelRect(0, 0, 1920, 1040);

        Assert.Throws<ArgumentOutOfRangeException>(() => PopupPlacement.Compute((PopupPosition)99, workArea, 360, 80, 16));
    }
}
