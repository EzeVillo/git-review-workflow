using GitReview.Domain;
using Xunit;
namespace GitReview.Host.Tests;
public class SaveReplyTests
{
    private const string Wire = "save-state\t1\nstatus\t2\nlist\tbranch\treview-saved/feature\t1\t0\t0\twalk\t2\t3\nconfig\tconfig\tbase\tmain\nconfig\tconfig\tremote\torigin\nsave-state\tcomplete\n";
    [Fact] public async Task Final_saved_state_replaces_all_primary_queries()
    {
        var cli = new FakeCliInvoker();
        var manager = new ReviewStateManager(cli, () => new[]{"/repo"});
        var state = await manager.RefreshPrimaryAsync(navigationOutput: Wire);
        Assert.Equal(new[]{"comments"}, cli.Verbs);
        Assert.Equal(Situation.NoReview, state.Situation);
        Assert.True(state.BranchesList.Single().Saved);
        Assert.Equal(2, state.BranchesList.Single().Position);
        Assert.Equal("main", state.Config!.Base);
    }
    [Fact] public async Task Save_requests_the_optional_reply_only_when_advertised()
    {
        var status = "state\treview/feature\tfeature\tdeadbeef\twhole\tnone\ncapability\tsave-state\nguard\t" + new string('a',40) + "\n";
        var cli = new FakeCliInvoker().Answer("status", status).Answer("--expect-state", Wire);
        var manager = new ReviewStateManager(cli, () => new[]{"/repo"});
        await manager.RefreshAsync(); cli.Calls.Clear();
        var result = await new MutationRunner(cli,manager,()=>"/repo").RunActionAsync("saveReview");
        Assert.Equal(0,result!.ExitCode);
        Assert.Equal(new[]{"--expect-state","comments"}, cli.Verbs);
        Assert.Equal(new[]{new string('a',40),"save","--porcelain"},cli.Calls[0].Args);
        Assert.Equal(Situation.NoReview, manager.Current.Situation);
    }
    [Fact] public async Task Invalid_replies_refresh_without_repeating_save()
    {
        foreach (var bad in new[]{"", Wire.Replace("save-state\tcomplete\n",""), Wire+"save-state\tcomplete\n",
            Wire.Replace("status\t2","status\t0"), Wire.Replace("list\tbranch","unknown\tbranch"),
            Wire.Replace("config\tconfig\tremote\torigin\n","")})
        {
            Assert.Null(SaveReply.Parse(bad));
            var cli = new FakeCliInvoker().Answer("status","",2);
            await new ReviewStateManager(cli,()=>new[]{"/repo"}).RefreshPrimaryAsync(navigationOutput:bad);
            Assert.Equal(new[]{"--version","status","list","config","comments"},cli.Verbs);
        }
        Assert.NotNull(SaveReply.Parse(Wire.Replace("\n","\r\n")));
    }
}
