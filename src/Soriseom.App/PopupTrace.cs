using System.Diagnostics;
using System.Globalization;

namespace Soriseom.App;

// Debug builds only. The smoke script saves these lines to tell why a popup did not appear,
// so a message must never hold a title, an artist or an app ID. See docs/ADR.md ADR-009.
internal static class PopupTrace
{
    private const string Prefix = "SoriseomTrace ";

    [Conditional("DEBUG")]
    public static void Write(string message) => Debug.WriteLine(Prefix + message);

    [Conditional("DEBUG")]
    public static void Failure(string what, Exception exception) =>
        Write($"{what} failed {exception.GetType().Name} 0x{exception.HResult:X8}");

    // String hashes differ per process, so equal values mean equal text only within one run.
    public static string Mask(string? text) => string.IsNullOrEmpty(text)
        ? "empty"
        : text.GetHashCode(StringComparison.Ordinal).ToString("X8", CultureInfo.InvariantCulture);
}
