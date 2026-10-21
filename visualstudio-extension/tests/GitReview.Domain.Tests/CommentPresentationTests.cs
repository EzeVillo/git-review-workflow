using Xunit;

namespace GitReview.Domain.Tests;

public sealed class CommentPresentationTests
{
    [Fact] public void ProseAndLocationUseOriginalOrdinalAndDecodeOnlyOnce() {
        var report=Comments.Parse("comment-entry\t2\t7\t4\tFile\ncomment-scope\t2\tselection\tbase\ncomment-path\t2\tbase\told%25name\ncomment-location\t2\tbase\t3\t5\ncomment-body\t2\t    100%25 and %2509\ncomment-body\t2\t\ncomment-body\t2\tSecond%09paragraph");
        var view=CommentPresentations.Present(report,report.Records("comment-entry").Single());
        Assert.Equal("    100% and %09\n\nSecond\tparagraph",view.Body);
        Assert.Equal("old%name:3–5 · Previous version",view.Location);
        Assert.Equal(2,view.Ordinal);
        Assert.True(view.CanOpenDiff);
        Assert.Equal("7. File · old%name:3–5 · Previous version",view.Label);
    }
    [Fact] public void MissingMetadataDoesNotInventGeneralScope() {
        var report=Comments.Parse("comment-entry\t1\t1\t1\tManual\ncomment-entry\t2\t1\t4\tGeneral\ncomment-scope\t2\tgeneral\t\ncomment-body\t2\tWhole review");
        Assert.Equal(CommentsCopy.locationUnavailable,CommentPresentations.Present(report,report.Records("comment-entry").First()).Location);
        Assert.False(CommentPresentations.Present(report,report.Records("comment-entry").First()).CanOpenDiff);
        Assert.False(CommentPresentations.Present(report,report.Records("comment-entry").Last()).CanOpenDiff);
        Assert.Equal(CommentsCopy.general,CommentPresentations.Present(report,report.Records("comment-entry").Last()).Location);
    }

    [Fact] public void LongUnicodePreviewKeepsFullBodyAndSeparatesUnsavedWarning() {
        var body = string.Concat(Enumerable.Repeat("🙂",161));
        var report = Comments.Parse("comment-entry\t1\t1\t1\tsrc/file.cs\ncomment-scope\t1\tselection\thead\ncomment-path\t1\thead\tsrc/file.cs\ncomment-location\t1\thead\t3\t7\ncomment-version\t1\tabcdef123456\t123456abcdef\ncomment-unversioned\t1\ncomment-body\t1\t"+body);
        var view = CommentPresentations.Present(report,report.Records("comment-entry").Single());
        Assert.Equal(body,view.Body);
        Assert.Equal(string.Concat(Enumerable.Repeat("🙂",159))+"…",view.Preview);
        Assert.Equal("1. src/file.cs:3–7 · New version",view.Label);
        Assert.Equal("Original changes · abcdef12 → 123456ab",view.Version);
        Assert.Equal(CommentsCopy.originalUnversioned,view.Warning);
    }
}
