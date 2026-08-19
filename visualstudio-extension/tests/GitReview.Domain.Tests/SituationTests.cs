using Xunit;

namespace GitReview.Domain.Tests;

public class SituationTests
{
    [Fact]
    public void Exit_codes_map_to_situations()
    {
        Assert.Equal(Situation.Review, SituationIds.ForExitCode(0));
        Assert.Equal(Situation.NoReview, SituationIds.ForExitCode(2));
        Assert.Equal(Situation.OutOfRange, SituationIds.ForExitCode(3));
        Assert.Equal(Situation.Error, SituationIds.ForExitCode(1));
        // Anything unknown is an error, never a review: the panel would otherwise
        // draw a review out of an exit code nobody defined.
        Assert.Equal(Situation.Error, SituationIds.ForExitCode(null));
        Assert.Equal(Situation.Error, SituationIds.ForExitCode(128));
    }

    [Fact]
    public void Finish_records_override_only_their_own_base()
    {
        Assert.Equal(Situation.FinishConflict, SituationIds.For(0, true, false));
        Assert.Equal(Situation.FinishPending, SituationIds.For(2, false, true));
        // A pending finish does not turn an active review into one, nor the reverse.
        Assert.Equal(Situation.Review, SituationIds.For(0, false, true));
        Assert.Equal(Situation.NoReview, SituationIds.For(2, true, false));
        // And neither of them rescues an out-of-range cursor.
        Assert.Equal(Situation.OutOfRange, SituationIds.For(3, true, true));
        Assert.Equal(Situation.Error, SituationIds.For(1, true, true));
    }

    [Fact]
    public void Only_review_and_finish_conflict_are_readable()
    {
        Assert.True(SituationIds.IsReviewReadable(Situation.Review));
        Assert.True(SituationIds.IsReviewReadable(Situation.FinishConflict));
        foreach (var s in Enum.GetValues<Situation>())
        {
            if (s is Situation.Review or Situation.FinishConflict) continue;
            Assert.False(SituationIds.IsReviewReadable(s), $"{s.Id()} is not a readable review");
        }
    }

    /// <summary>
    /// The ids are the wire names the contract and the other two clients use, so a
    /// typo in either direction is a situation the panel silently cannot resolve.
    /// </summary>
    [Fact]
    public void Ids_round_trip_for_every_situation()
    {
        foreach (var s in Enum.GetValues<Situation>())
            Assert.Equal(s, SituationIds.FromId(s.Id()));
        Assert.Null(SituationIds.FromId("no-such-situation"));
        Assert.Equal(8, Enum.GetValues<Situation>().Length);
    }
}
