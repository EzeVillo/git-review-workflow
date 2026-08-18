#if NET472
namespace GitReview.VS.ToolWindows;

/// <summary>
/// `Dictionary.GetValueOrDefault` is .NET Core 2.0+. Declared in the namespace that
/// uses it (PanelView's section state), so the panel code reads the same on both
/// target frameworks.
/// </summary>
internal static class DictionaryCompat
{
    public static TValue GetValueOrDefault<TKey, TValue>(
        this Dictionary<TKey, TValue> source,
        TKey key,
        TValue defaultValue)
        where TKey : notnull =>
        source.TryGetValue(key, out var value) ? value : defaultValue;
}

/// <summary>
/// Same idea for the string overloads .NET Core grew: extension methods do not cross
/// assemblies, so the domain's shim does not serve this one.
/// </summary>
internal static class StringCompat
{
    public static bool Contains(this string s, string value, StringComparison comparison) =>
        s.IndexOf(value, comparison) >= 0;
}
#endif
