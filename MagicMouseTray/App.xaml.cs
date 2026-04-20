// SPDX-License-Identifier: MIT
using System.Windows;

namespace MagicMouseTray;

public partial class App
{
    TrayApp? _trayApp;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        _trayApp = new TrayApp(Config.Load());
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayApp?.Dispose();
        base.OnExit(e);
    }
}
