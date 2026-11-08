namespace GitReview.Domain;
public sealed record CommentPaths(IReadOnlyList<string>? Paths)
{
    public static bool Supported(string output) => output.Replace("\r\n","\n").Split('\n').Count(x=>x=="capability\tcomments-paths")==1;
    public static CommentPaths? Parse(string output, string guard)
    {
        var lines=output.Replace("\r\n","\n").Split('\n').ToList();
        if(lines.Count>0 && lines[lines.Count-1]=="")lines.RemoveAt(lines.Count-1);
        if(lines.Count<2)return null;
        var head=lines[0].Split('\t');
        const string token="^(?:[0-9a-f]{40}|[0-9a-f]{64})$";
        if(head.Length!=4 || head[0]!="comments-paths" || head[1]!="1" ||
            !System.Text.RegularExpressions.Regex.IsMatch(guard,token) || head[2]!=guard || lines[lines.Count-1]!="comments-paths\tcomplete")return null;
        if(head[3]=="legacy")return lines.Count==2?new CommentPaths((IReadOnlyList<string>?)null):null;
        if(!System.Text.RegularExpressions.Regex.IsMatch(head[3],token) || lines.Count!=4)return null;
        var paths=new List<string>();
        var kinds=new[]{"local","shared"};
        for(var i=0;i<2;i++)
        {
            var prefix="comments-path\t"+kinds[i]+"\t";
            if(!lines[i+1].StartsWith(prefix,StringComparison.Ordinal))return null;
            var raw=lines[i+1].Substring(prefix.Length);
            if(raw.Length==0 || System.Text.RegularExpressions.Regex.IsMatch(raw,"%(?!25|09|0A|0D|3E)"))return null;
            paths.Add(Uri.UnescapeDataString(raw));
        }
        return new CommentPaths(paths);
    }
}
