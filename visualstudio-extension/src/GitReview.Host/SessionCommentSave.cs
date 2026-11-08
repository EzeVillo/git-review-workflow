using GitReview.Domain;

namespace GitReview.Host;

public static class SessionCommentSave
{
    public static async Task<bool> SaveAsync(CliInvoker cli, string cwd, ReviewState state, string action,
        ActionParams? parameters, Func<Task<bool?>>? hasUnsaved, Func<string,Task<bool>> save)
    {
        var housekeeping=(parameters as ActionParams.Housekeeping)?.Action;
        var relevant=action is "saveReview" or "abortReview" or "finishReview" or "undoFinish" or "resumeFinish" ||
            housekeeping?.Kind is HousekeepingKind.CleanOne or HousekeepingKind.CleanKeepFixes or HousekeepingKind.CleanAll or HousekeepingKind.ForgetSavedOne or HousekeepingKind.ForgetSavedAll;
        if(!relevant)return true;
        if(hasUnsaved is not null)
        {
            try { if(await hasUnsaved().ConfigureAwait(true)==false)return true; }
            catch(Exception) { /* Unknown keeps the selective save path. */ }
        }
        var response=await cli.InvokeAsync("comments",new[]{"status","--porcelain","--all"},cwd).ConfigureAwait(true);
        if(response.ExitCode!=0 || response.TimedOut || response.ErrorCode is not null)return false;
        var report=Comments.Parse(response.Stdout);
        var saved=housekeeping?.Kind is HousekeepingKind.ForgetSavedOne or HousekeepingKind.ForgetSavedAll;
        var prefix=saved?"review-saved/":"review/";
        var source=housekeeping?.Source ?? state.State?.Source ?? state.FixesList.FirstOrDefault(f=>f.Current)?.Name?.Substring("review-fixes/".Length);
        var all=housekeeping?.Kind is HousekeepingKind.CleanAll or HousekeepingKind.ForgetSavedAll;
        var owners=report.Records("comments-owner").Where(r=>r.Count>=3 && (all ? r[2].StartsWith(prefix,StringComparison.Ordinal) : r[2]==prefix+source)).Select(r=>r[2]).ToArray();
        foreach(var doc in Comments.OwnedBy(report,owners))if(!await save(doc.Path).ConfigureAwait(true))return false;
        return true;
    }
}
