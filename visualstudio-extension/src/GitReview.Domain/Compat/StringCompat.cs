#if NET472
namespace GitReview.Domain;

/// <summary>
/// BCL methods the domain calls that .NET Core grew and .NET Framework never did.
/// Declared in the domain's own namespace so callers need no extra using and read
/// identically on both target frameworks — on net8.0 the instance methods win and
/// this file is not compiled at all.
/// </summary>
internal static class StringCompat
{
    public static bool Contains(this string s, string value, StringComparison comparison) =>
        s.IndexOf(value, comparison) >= 0;

    public static bool Contains(this string s, char value) => s.IndexOf(value) >= 0;

    public static bool StartsWith(this string s, char value) => s.Length > 0 && s[0] == value;

    public static bool EndsWith(this string s, char value) => s.Length > 0 && s[s.Length - 1] == value;
}

internal static class DictionaryCompat
{
    public static TValue GetValueOrDefault<TKey, TValue>(
        this IReadOnlyDictionary<TKey, TValue> source,
        TKey key,
        TValue defaultValue) =>
        source.TryGetValue(key, out var value) ? value : defaultValue;

    public static TValue GetValueOrDefault<TKey, TValue>(
        this Dictionary<TKey, TValue> source,
        TKey key,
        TValue defaultValue)
        where TKey : notnull =>
        source.TryGetValue(key, out var value) ? value : defaultValue;
}
#endif
