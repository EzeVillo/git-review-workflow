namespace GitReview.Domain;

/// <summary>
/// Platform questions the domain asks, answered per target framework.
/// `OperatingSystem.IsWindows()` is .NET 5+; the net472 target exists only to be
/// loaded in-proc by devenv, which is Windows by construction.
/// </summary>
public static class RuntimeInfo
{
#if NET472
    public static bool IsWindows => true;
#else
    public static bool IsWindows => OperatingSystem.IsWindows();
#endif
}
