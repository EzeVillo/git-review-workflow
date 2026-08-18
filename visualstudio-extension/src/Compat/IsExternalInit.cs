// Record positional parameters and `init` accessors need this marker type, which
// .NET Framework's BCL does not ship. Linked into every assembly that declares a
// record when the net472 (in-proc Visual Studio) target framework is built; the
// net8.0 targets get it from the BCL and never compile this file.
//
// Do not add anything else here: one file, one missing BCL type.

namespace System.Runtime.CompilerServices
{
    internal static class IsExternalInit
    {
    }
}
