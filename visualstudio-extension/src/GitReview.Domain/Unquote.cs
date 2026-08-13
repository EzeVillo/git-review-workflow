using System.Text;

namespace GitReview.Domain;

/// <summary>
/// Undoes git C-style quoting applied when a path contains " or \
/// (core.quotePath=false). One-way: never re-quote the result.
/// </summary>
public static class Unquote
{
    public static string UnquotePath(string raw)
    {
        if (!raw.StartsWith('"') || !raw.EndsWith('"') || raw.Length < 2)
            return raw;

        var inner = raw.Substring(1, raw.Length - 2);
        var chunks = new List<byte[]>();
        var octalRun = new List<int>();

        void FlushOctal()
        {
            if (octalRun.Count == 0) return;
            chunks.Add(octalRun.Select(b => (byte)b).ToArray());
            octalRun.Clear();
        }

        var i = 0;
        while (i < inner.Length)
        {
            var ch = inner[i];
            if (ch == '\\' && i + 1 < inner.Length)
            {
                var next = inner[i + 1];
                if (next is >= '0' and <= '7')
                {
                    var end = Math.Min(i + 4, inner.Length);
                    var octalDigits = inner.Substring(i + 1, end - (i + 1));
                    var digits = new StringBuilder();
                    foreach (var c in octalDigits)
                    {
                        if (c is >= '0' and <= '7' && digits.Length < 3) digits.Append(c);
                        else break;
                    }
                    if (digits.Length > 0)
                    {
                        octalRun.Add(Convert.ToInt32(digits.ToString(), 8) & 0xff);
                        i += 1 + digits.Length;
                        continue;
                    }
                }
                FlushOctal();
                var decoded = next switch
                {
                    '\\' => "\\",
                    '"' => "\"",
                    'a' => "\u0007",
                    'b' => "\b",
                    'f' => "\u000c",
                    'n' => "\n",
                    'r' => "\r",
                    't' => "\t",
                    'v' => "\u000b",
                    _ => next.ToString(),
                };
                chunks.Add(Encoding.UTF8.GetBytes(decoded));
                i += 2;
                continue;
            }

            FlushOctal();
            // Handle surrogate pairs like Kotlin codePointAt
            if (char.IsHighSurrogate(inner[i]) && i + 1 < inner.Length && char.IsLowSurrogate(inner[i + 1]))
            {
                var pair = inner.Substring(i, 2);
                chunks.Add(Encoding.UTF8.GetBytes(pair));
                i += 2;
            }
            else
            {
                var s = inner[i].ToString();
                chunks.Add(Encoding.UTF8.GetBytes(s));
                i += 1;
            }
        }
        FlushOctal();

        var total = chunks.Sum(c => c.Length);
        var output = new byte[total];
        var offset = 0;
        foreach (var c in chunks)
        {
            Buffer.BlockCopy(c, 0, output, offset, c.Length);
            offset += c.Length;
        }
        return Encoding.UTF8.GetString(output);
    }

    public static PathRef ToPathRef(string raw) => new(raw, UnquotePath(raw));
}

/// <summary>Path as emitted by porcelain (raw) vs UI/filesystem (display).</summary>
public sealed record PathRef(
    /// <summary>What goes back to the CLI (status --why &lt;raw&gt;).</summary>
    string Raw,
    /// <summary>What the user sees; also filesystem path base.</summary>
    string Display);
