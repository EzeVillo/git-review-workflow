#if NET472
namespace GitReview.Host;

/// <summary>
/// Host-side twin of the domain's shim: `string.Contains(string, StringComparison)`
/// is .NET Core 2.1+, and extension methods do not cross assemblies for free.
/// </summary>
internal static class StringCompat
{
    public static bool Contains(this string s, string value, StringComparison comparison) =>
        s.IndexOf(value, comparison) >= 0;
}
#endif
