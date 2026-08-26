using Xunit;

namespace GitReview.Domain.Tests;

public class CliMessageTests
{
    /// <summary>
    /// The case that produced the function: pressing the offer and seeing nothing.
    /// The verb's outcome travels on stdout and this path read stderr alone.
    /// </summary>
    [Fact]
    public void The_verb_outcome_cannot_be_lost_because_it_comes_on_stdout()
    {
        Assert.Equal(
            "updated the file: 1 kept, 1 added, 0 dropped",
            CliMessage.DraftOutcomeText("updated the file: 1 kept, 1 added, 0 dropped\n", ""));
    }

    [Fact]
    public void With_a_note_the_outcome_comes_first()
    {
        var msg = CliMessage.DraftOutcomeText(
            "updated the file: 2 kept, 0 added, 0 dropped\n",
            "note: no authoring guide. Create one with:\n        git review walkthrough guide\n");
        Assert.Equal(
            "updated the file: 2 kept, 0 added, 0 dropped — "
            + "note: no authoring guide. Create one with: git review walkthrough guide",
            msg);
        // The separator sits BETWEEN the two parts, never inside either.
        Assert.Equal(2, msg.Split(" — ").Length);
    }

    [Fact]
    public void An_empty_stream_leaves_no_dangling_separator()
    {
        Assert.Equal("note: solo la nota", CliMessage.DraftOutcomeText("", "note: solo la nota"));
        Assert.Equal("", CliMessage.DraftOutcomeText("", ""));
        Assert.Equal("", CliMessage.DraftOutcomeText("  \n \n", "\n"));
    }
}
