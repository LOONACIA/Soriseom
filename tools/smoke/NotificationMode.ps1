# Prints the current ToastNotificationManagerForUser.NotificationMode.
# Windows PowerShell 5.1 only: pwsh 7 has no WinRT projection.
$ErrorActionPreference = 'Stop'

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[Windows.UI.Notifications.ToastNotificationManager]::GetDefault().NotificationMode.ToString()
