using System.Diagnostics;
using Windows.ApplicationModel;

namespace Soriseom.App;

internal static class StartupRegistration
{
    private const string TaskId = "SoriseomStartup";

    public static async Task<StartupTaskState?> GetStateAsync()
    {
        try
        {
            var task = await StartupTask.GetAsync(TaskId);
            return task.State;
        }
        catch (Exception ex)
        {
            Debug.WriteLine(ex);
            return null;
        }
    }

    public static async Task<StartupTaskState?> SetEnabledAsync(bool enabled)
    {
        try
        {
            var task = await StartupTask.GetAsync(TaskId);
            if (enabled)
            {
                return await task.RequestEnableAsync();
            }

            task.Disable();
            return task.State;
        }
        catch (Exception ex)
        {
            Debug.WriteLine(ex);
            return null;
        }
    }
}
