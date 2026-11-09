using GitReview.Domain;
using Xunit;
namespace GitReview.Host.Tests;

public class ContinueReplyTests
{
    private static readonly string Guard=new('a',40);
    private static readonly string Body=$"state\treview/feature\tfeature\tdeadbeef\twhole\tnone\ncapability\tsave-state\nguard\t{Guard}\n";
    private static readonly string Wire=$"continue-state\t1\n{Body}continue-state\tcomplete\n";
    private static readonly string Inventory=$"capability\tcontinue-state\ncontinue-guard\t{Guard}\nbranch\treview-saved/feature\t1\t0\t0\twhole\n";

    [Fact] public async Task Continue_uses_the_inventory_token_and_reuses_its_final_state()
    {
        var cli=new FakeCliInvoker().Answer("status","",2).Answer("list",Inventory).Answer("--expect-state",Wire);
        var manager=new ReviewStateManager(cli,()=>new[]{"/repo"});
        await manager.RefreshAsync();
        Assert.Equal(Guard,manager.Current.ContinueGuard);
        var token=StaleGuard.CaptureToken(manager.Current);
        Assert.False(StaleGuard.TokenStillValid(token,manager.Current with {ContinueGuard=new string('b',40)}));
        cli.Calls.Clear();
        await manager.ReadForMutationAsync(continueAction:true);
        Assert.Empty(cli.Calls);
        var result=await new MutationRunner(cli,manager,()=>"/repo").RunActionAsync("continueReview",new ActionParams.Continue("feature"),expected:token);
        Assert.Equal(0,result!.ExitCode);
        Assert.Equal(new[]{"--expect-state","comments"},cli.Verbs);
        Assert.Equal(new[]{Guard,"continue","feature","--porcelain"},cli.Calls[0].Args);
        Assert.Equal(Situation.Review,manager.Current.Situation);
        Assert.True(manager.Current.SaveState);
        Assert.Null(manager.Current.ContinueGuard);
    }
    [Fact] public async Task Incomplete_replies_fall_back_without_repeating_continue()
    {
        Assert.True(ContinueReply.IsValid(Wire.Replace("\n","\r\n")));
        foreach(var bad in new[]{"",Body,Wire+"\n",Wire.Replace("continue-state\tcomplete\n",""),Wire+"continue-state\tcomplete\n",Wire.Replace(Body,Body+Body),Wire.Replace("review/feature","main")})
        {
            Assert.False(ContinueReply.IsValid(bad));
            var cli=new FakeCliInvoker().Answer("status","",2);
            await new ReviewStateManager(cli,()=>new[]{"/repo"}).RefreshPrimaryAsync(navigationOutput:bad);
            Assert.Equal(new[]{"--version","status","list","config","comments"},cli.Verbs);
        }
    }
    [Fact] public void Inventory_requires_both_capability_and_an_unambiguous_token()
    {
        Assert.Equal(Guard,ContinueReply.ParseGuard(Inventory));
        foreach(var bad in new[]{"",Inventory+Inventory,Inventory.Replace(Guard,"bad"),Inventory.Replace(Guard,Guard+" "),Inventory.Replace("capability\tcontinue-state\n","")}) Assert.Null(ContinueReply.ParseGuard(bad));
    }
}
