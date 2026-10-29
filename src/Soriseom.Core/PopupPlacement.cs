namespace Soriseom.Core;

public static class PopupPlacement
{
    public static PixelRect Compute(PopupPosition position, PixelRect workArea, int width, int height, int margin)
    {
        int x = position switch
        {
            PopupPosition.TopLeft or PopupPosition.BottomLeft => workArea.X + margin,
            PopupPosition.TopCenter or PopupPosition.BottomCenter => workArea.X + ((workArea.Width - width) / 2),
            PopupPosition.TopRight or PopupPosition.BottomRight => workArea.X + workArea.Width - width - margin,
            _ => throw new ArgumentOutOfRangeException(nameof(position), position, null),
        };

        int y = position switch
        {
            PopupPosition.TopLeft or PopupPosition.TopCenter or PopupPosition.TopRight => workArea.Y + margin,
            PopupPosition.BottomLeft or PopupPosition.BottomCenter or PopupPosition.BottomRight => workArea.Y + workArea.Height - height - margin,
            _ => throw new ArgumentOutOfRangeException(nameof(position), position, null),
        };

        return new PixelRect(x, y, width, height);
    }
}
