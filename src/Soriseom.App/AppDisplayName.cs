using System.Diagnostics;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.Shell;

namespace Soriseom.App;

internal static class AppDisplayName
{
    public static unsafe string Resolve(string appId)
    {
        Guid folder = PInvoke.FOLDERID_AppsFolder;
        Guid shellItemId = IShellItem.IID_Guid;
        void* shellItem;
        fixed (char* name = appId)
        {
            HRESULT result = PInvoke.SHCreateItemInKnownFolder(&folder, 0, name, &shellItemId, &shellItem);
            if (result.Failed)
            {
                Debug.WriteLine($"Could not resolve app display name for {appId}: {result}");
                return appId;
            }
        }

        var item = (IShellItem*)shellItem;
        try
        {
            PWSTR displayName;
            item->GetDisplayName(SIGDN.SIGDN_NORMALDISPLAY, &displayName);
            try
            {
                var name = displayName.ToString();
                return string.IsNullOrWhiteSpace(name) ? appId : name;
            }
            finally
            {
                PInvoke.CoTaskMemFree(displayName);
            }
        }
        catch (Exception exception)
        {
            Debug.WriteLine(exception);
            return appId;
        }
        finally
        {
            item->Release();
        }
    }
}
