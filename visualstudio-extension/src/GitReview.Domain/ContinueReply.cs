namespace GitReview.Domain;

public static class ContinueReply
{
    public static string? ParseGuard(string output)
    {
        var lines=output.Replace("\r\n","\n").Split('\n');
        if(lines.Count(line=>line=="capability\tcontinue-state")!=1)return null;
        var guards=lines.Where(line=>line.StartsWith("continue-guard\t",StringComparison.Ordinal)).ToArray();
        if(guards.Length!=1)return null;
        var value=guards[0].Substring(15);
        return (value.Length is 40 or 64) && value.All(c=>c is >= '0' and <= '9' or >= 'a' and <= 'f') ? value : null;
    }

    public static bool IsValid(string output)
    {
        var normalized=output.Replace("\r\n","\n");
        if(normalized.EndsWith("\n",StringComparison.Ordinal))normalized=normalized.Substring(0,normalized.Length-1);
        var lines=normalized.Split('\n');
        if(lines[0]!="continue-state\t1" || lines[lines.Length-1]!="continue-state\tcomplete" ||
            lines.Count(line=>line.StartsWith("continue-state\t",StringComparison.Ordinal))!=2 ||
            lines.Count(line=>line.StartsWith("state\t",StringComparison.Ordinal))!=1 || StaleGuard.Parse(output) is null)return false;
        try
        {
            var parsed=Porcelain.ParsePorcelain(output);
            return parsed.State.Branch.StartsWith("review/",StringComparison.Ordinal) && parsed.Finish is null &&
                parsed.State.Mode is ReviewMode.Whole or ReviewMode.Step or ReviewMode.Walk;
        }
        catch { return false; }
    }
}
