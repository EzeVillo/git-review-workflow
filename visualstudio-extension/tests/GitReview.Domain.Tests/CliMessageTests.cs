using Xunit;

namespace GitReview.Domain.Tests;

public class CliMessageTests
{
    /// <summary>
    /// The case that produced the record: pressing the offer and seeing nothing.
    /// The verb's outcome travels on stdout, but reading its SENTENCE would be
    /// parsing human output; the three numbers arrive in fields.
    /// </summary>
    [Fact]
    public void Reads_the_three_numbers_of_the_record()
    {
        Assert.Equal(new MergedCounts(1, 2, 3), DraftFlow.ParseMergedRecord("merged\t1\t2\t3\n"));
    }

    [Fact]
    public void Finds_the_record_among_other_lines()
    {
        Assert.Equal(
            new MergedCounts(0, 1, 0),
            DraftFlow.ParseMergedRecord("otra\tcosa\nmerged\t0\t1\t0\n"));
    }

    /// <summary>
    /// Without the record the caller stays quiet: an old CLI prints the human
    /// sentence and nothing else, and there the right answer is no acknowledgement.
    /// </summary>
    [Fact]
    public void Without_the_record_it_returns_null_rather_than_inventing()
    {
        Assert.Null(DraftFlow.ParseMergedRecord(""));
        Assert.Null(DraftFlow.ParseMergedRecord("updated /tmp/x.md: 1 kept, 2 added, 3 dropped\n"));
        // The name alone is not enough: without the three fields there is no answer.
        Assert.Null(DraftFlow.ParseMergedRecord("merged\t1\t2\n"));
        // Nor is a field that is not a number.
        Assert.Null(DraftFlow.ParseMergedRecord("merged\t1\tdos\t3\n"));
    }

    [Fact]
    public void Names_the_three_things_when_the_three_happened()
    {
        Assert.Equal(
            "Reading order updated: 3 kept, 1 added, 2 no longer in the PR.",
            UserCopy.DraftUpdated(3, 1, 2));
    }

    /// <summary>
    /// Zeroes are not spelled out: making somebody read "0 added" to find out
    /// nothing was added is the noise this sentence exists to avoid.
    /// </summary>
    [Fact]
    public void Omits_the_zero_rather_than_enumerating_it()
    {
        Assert.Equal("Reading order updated: 3 kept, 1 added.", UserCopy.DraftUpdated(3, 1, 0));
        Assert.Equal(
            "Reading order updated: 3 kept, 2 no longer in the PR.",
            UserCopy.DraftUpdated(3, 0, 2));
    }

    /// <summary>
    /// An update that moves nothing is a real outcome, not a no-op: the range
    /// shifted without changing which files it touches. With no sentence there is
    /// no signal at all.
    /// </summary>
    [Fact]
    public void An_update_that_moved_nothing_still_says_what_happened()
    {
        Assert.Equal("Reading order updated: nothing moved, 4 kept.", UserCopy.DraftUpdated(4, 0, 0));
    }

    /// <summary>
    /// None of the three sentences names a command or a path: that was the stdout
    /// this acknowledgement replaces.
    /// </summary>
    [Fact]
    public void Names_no_command_and_no_path()
    {
        foreach (var text in new[]
                 {
                     UserCopy.DraftUpdated(3, 1, 2),
                     UserCopy.DraftUpdated(3, 1, 0),
                     UserCopy.DraftUpdated(4, 0, 0),
                 })
        {
            Assert.DoesNotContain("git review", text);
            Assert.DoesNotContain("/", text);
            Assert.StartsWith("Reading order updated:", text);
        }
    }
}
