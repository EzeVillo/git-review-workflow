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
#endif
