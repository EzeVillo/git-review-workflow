// `s[prefix.Length..]` compiles to Substring, but only if System.Index and
// System.Range exist — and .NET Framework's BCL has neither. Same deal as
// IsExternalInit: linked into every assembly built for net472 so the domain code
// reads the same on both target frameworks. Shape follows dotnet/runtime, since the
// compiler looks these types up by name and calls specific members.

#if NET472
namespace System
{
    internal readonly struct Index : IEquatable<Index>
    {
        private readonly int _value;

        public Index(int value, bool fromEnd = false)
        {
            if (value < 0) throw new ArgumentOutOfRangeException(nameof(value), "Non-negative number required.");
            _value = fromEnd ? ~value : value;
        }

        private Index(int value) => _value = value;

        public static Index Start => new Index(0);

        public static Index End => new Index(~0);

        public static Index FromStart(int value) =>
            value < 0
                ? throw new ArgumentOutOfRangeException(nameof(value), "Non-negative number required.")
                : new Index(value);

        public static Index FromEnd(int value) =>
            value < 0
                ? throw new ArgumentOutOfRangeException(nameof(value), "Non-negative number required.")
                : new Index(~value);

        public int Value => _value < 0 ? ~_value : _value;

        public bool IsFromEnd => _value < 0;

        public int GetOffset(int length) => IsFromEnd ? _value + length + 1 : _value;

        public override bool Equals(object? value) => value is Index other && _value == other._value;

        public bool Equals(Index other) => _value == other._value;

        public override int GetHashCode() => _value;

        public static implicit operator Index(int value) => FromStart(value);

        public override string ToString() => IsFromEnd ? "^" + Value.ToString() : Value.ToString();
    }

    internal readonly struct Range : IEquatable<Range>
    {
        public Index Start { get; }

        public Index End { get; }

        public Range(Index start, Index end)
        {
            Start = start;
            End = end;
        }

        public static Range StartAt(Index start) => new Range(start, Index.End);

        public static Range EndAt(Index end) => new Range(Index.Start, end);

        public static Range All => new Range(Index.Start, Index.End);

        public (int Offset, int Length) GetOffsetAndLength(int length)
        {
            var start = Start.IsFromEnd ? length - Start.Value : Start.Value;
            var end = End.IsFromEnd ? length - End.Value : End.Value;
            if ((uint)end > (uint)length || (uint)start > (uint)end)
                throw new ArgumentOutOfRangeException(nameof(length));
            return (start, end - start);
        }

        public override bool Equals(object? value) =>
            value is Range other && other.Start.Equals(Start) && other.End.Equals(End);

        public bool Equals(Range other) => other.Start.Equals(Start) && other.End.Equals(End);

        public override int GetHashCode() => (Start.GetHashCode() * 31) + End.GetHashCode();

        public override string ToString() => Start + ".." + End;
    }
}
#endif
