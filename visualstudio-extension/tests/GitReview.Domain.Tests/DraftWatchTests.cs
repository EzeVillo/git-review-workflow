using GitReview.Domain;
using Xunit;

namespace GitReview.Domain.Tests;

public class DraftWatchTests
{
    private static DraftRecord Draft(string path) =>
        new("x", path, 0, 1, DraftSource.Remote, DraftRange.Full, DraftState.Fresh);

    private static ReviewState State(string? draftPath = null, IReadOnlyList<DraftRecord>? drafts = null) =>
        new(Situation.NoReview, Drafts: drafts, DraftPath: draftPath);

    [Fact]
    public void NothingToWatchWithoutDrafts()
    {
        Assert.Empty(DraftWatch.WatchDirs(State()));
        Assert.Empty(DraftWatch.WatchDirs(State(drafts: Array.Empty<DraftRecord>())));
    }

    [Fact]
    public void OneDirectoryPerReportedPath()
    {
        Assert.Equal(
            new[] { "/repo/.git/review-walkthrough", "/repo/.git/review-walkthrough/feature" },
            DraftWatch.WatchDirs(State(drafts: new[]
            {
                Draft("/repo/.git/review-walkthrough/feature/checkout.md"),
                Draft("/repo/.git/review-walkthrough/telemetry.md"),
            })));
    }

    [Fact]
    public void TheActiveReviewDraftCountsToo()
    {
        Assert.Equal(
            new[] { "/repo/.git/review-walkthrough/feature" },
            DraftWatch.WatchDirs(State(draftPath: "/repo/.git/review-walkthrough/feature/x.md")));
    }

    [Fact]
    public void OneDirectoryEvenWhenBothReportIt()
    {
        Assert.Equal(
            new[] { "/repo/.git/review-walkthrough/feature" },
            DraftWatch.WatchDirs(State(
                draftPath: "/repo/.git/review-walkthrough/feature/x.md",
                drafts: new[]
                {
                    Draft("/repo/.git/review-walkthrough/feature/x.md"),
                    Draft("/repo/.git/review-walkthrough/feature/y.md"),
                })));
    }

    [Fact]
    public void OrderIsStableNotOrderOfAppearance()
    {
        var one = DraftWatch.WatchDirs(State(drafts: new[] { Draft("/r/b/x.md"), Draft("/r/a/y.md") }));
        var other = DraftWatch.WatchDirs(State(drafts: new[] { Draft("/r/a/y.md"), Draft("/r/b/x.md") }));
        Assert.Equal(new[] { "/r/a", "/r/b" }, one);
        Assert.Equal(one, other);
    }

    [Fact]
    public void WindowsSeparatorsSplitTheSameWay()
    {
        Assert.Equal(
            new[] { @"C:\repo\.git\review-walkthrough\feature" },
            DraftWatch.WatchDirs(State(draftPath: @"C:\repo\.git\review-walkthrough\feature\x.md")));
    }

    [Fact]
    public void APathThatNamesNoDirectoryIsDropped()
    {
        Assert.Empty(DraftWatch.WatchDirs(State(draftPath: "")));
        Assert.Empty(DraftWatch.WatchDirs(State(draftPath: "   ")));
        Assert.Empty(DraftWatch.WatchDirs(State(draftPath: "x.md")));
        Assert.Empty(DraftWatch.WatchDirs(State(draftPath: "/x.md")));
    }
}
