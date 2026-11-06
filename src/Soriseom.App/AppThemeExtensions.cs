using Microsoft.UI.Xaml;
using Soriseom.Core;

namespace Soriseom.App;

internal static class AppThemeExtensions
{
    public static ElementTheme ToElementTheme(this AppTheme theme) => theme switch
    {
        AppTheme.Light => ElementTheme.Light,
        AppTheme.Dark => ElementTheme.Dark,
        _ => ElementTheme.Default,
    };
}
