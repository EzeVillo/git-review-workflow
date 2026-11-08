using GitReview.Host;
using Xunit;

public class RefreshGateTests
{
    [Fact] public void FinalPrimaryCoversEarlierMutationSignals()
    {
        var gate = new RefreshGate();
        gate.MutationChanged(true);
        for(var i=0;i<4;i++) { gate.Request(); Assert.False(gate.TryStart()); }
        gate.PrimaryStarting(); gate.MutationChanged(false);
        Assert.False(gate.TryStart());
    }
    [Fact] public void LaterChangesGetOneFollowupWithoutParallelReads()
    {
        var gate = new RefreshGate();
        gate.MutationChanged(true); gate.PrimaryStarting();
        for(var i=0;i<4;i++) gate.Request();
        Assert.False(gate.TryStart());
        gate.MutationChanged(false);
        Assert.True(gate.TryStart()); Assert.False(gate.TryStart());
        gate.Finished(); Assert.False(gate.TryStart());
    }
    [Fact] public void NoPrimaryAndQueuedOrInflightReadsKeepTheirSignals()
    {
        var gate = new RefreshGate();
        gate.Request(); gate.MutationChanged(true); Assert.False(gate.TryStart());
        gate.MutationChanged(false); Assert.True(gate.TryStart());
        gate.Request(); gate.MutationChanged(true); gate.Finished(); Assert.False(gate.TryStart());
        gate.MutationChanged(false); Assert.True(gate.TryStart());
        gate.Request(); Assert.False(gate.TryStart());
        gate.Finished(); Assert.True(gate.TryStart());
    }
}
