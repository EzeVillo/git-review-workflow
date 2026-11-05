using Xunit;
namespace GitReview.Domain.Tests;
public class CommentsTests
{
    [Fact] public void Pending_comments_have_no_empty_states_or_document_controls()
    {
        var model = GitReview.Fixtures.PanelFixtures.NoReviewReady() with {Comments = new CommentsReport(Array.Empty<CommentRow>(), Loading: true)};
        var section = Assert.Single(PanelLayoutBuilder.PanelLayout(model).Blocks.OfType<Block.ToolsSection>(), b => b.Title == CommentsCopy.title);
        Assert.Equal(CommentsCopy.reading, Assert.Single(section.NestedBlocks.OfType<Block.Paragraph>()).Text);
        Assert.Empty(section.NestedBlocks.OfType<Block.GuideRows>());
        Assert.Empty(section.NestedBlocks.OfType<Block.Row>());
    }
    [Fact] public void Copy_path_belongs_only_to_existing_local_documents_in_every_context()
    {
        foreach (var kind in new[]{"review", "compare"}) foreach (var state in new[]{"active", "result", "repository"}) {
            var report = Comments.Parse($"comments-context\tc\t{kind}\t{state}\tg\tFeature\ncomments-document\t/absent\tc\tlocal\tabsent\tabsent\ncomments-document\t/local\tc\tlocal\tpresent\tunreadable\ncomments-document\t/shared\tc\tshared\tpresent\ts");
            var baseline = state == "active" ? GitReview.Fixtures.PanelFixtures.ReviewWhole() : GitReview.Fixtures.PanelFixtures.NoReviewReady();
            var model = baseline with {Comments = report};
            var controls = PanelLayoutBuilder.PanelLayout(model).CollectControls().ToList();
            var copy = Assert.Single(controls, c => c.Id == ControlId.CopyCommentPath);
            Assert.Equal(1, copy.Index);
            Assert.Equal(Emphasis.Icon, copy.Emphasis);
            Assert.Equal("Copy path", copy.AccessibleName);
            Assert.Equal("Copy this document's path", copy.Tooltip);
            Assert.True(copy.Enabled);
            Assert.Equal(ControlId.OpenComments, controls[controls.IndexOf(copy) - 1].Id);
            Assert.False(Assert.Single(PanelLayoutBuilder.PanelLayout(model with {Busy = true}).CollectControls(), c => c.Id == ControlId.CopyCommentPath).Enabled);
        }
    }
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Main_panel_keeps_independent_empty_states_after_reading(bool setup)
    {
        var model=GitReview.Fixtures.PanelFixtures.NoReviewReady() with {NoBaseConfigured=setup,Comments=Comments.Parse("")};
        var section=PanelLayoutBuilder.PanelLayout(model).Blocks.OfType<Block.ToolsSection>().Single(b=>b.Title==CommentsCopy.title);
        var rows=section.NestedBlocks.OfType<Block.GuideRows>().SelectMany(b=>b.Rows).ToArray();
        Assert.Equal(new[]{"Local","Shared"},rows.Select(r=>r.Name));
        Assert.Equal(new[]{"No local comments.","No shared comments."},rows.Select(r=>r.Badge));
        Assert.All(rows,r=>Assert.Empty(r.Controls));
    }
    [Theory]
    [InlineData("local")]
    [InlineData("shared")]
    public void Missing_kind_stays_visible_without_changing_document_indices(string kind)
    {
        var report=Comments.Parse($"comments-context\tc\treview\tresult\tg\tFeature\ncomments-document\t/l\tc\tlocal\tabsent\tabsent\ncomments-document\t/s\tc\t{kind}\tpresent\tr");
        var layout=PanelLayoutBuilder.PanelLayout(GitReview.Fixtures.PanelFixtures.NoReviewReady() with {Comments=report});
        var section=layout.Blocks.OfType<Block.ToolsSection>().Single(b=>b.Title==CommentsCopy.title);
        var rows=section.NestedBlocks.OfType<Block.GuideRows>().SelectMany(b=>b.Rows).ToArray();
        Assert.Equal(2,rows.Length);
        Assert.Contains(rows,r=>r.Badge==(kind=="local" ? CommentsCopy.emptyShared : CommentsCopy.emptyLocal));
        Assert.Equal(1,layout.CollectControls().Single(c=>c.Id==ControlId.OpenComments).Index);
    }
    [Fact] public void Unread_and_failed_queries_never_claim_there_are_no_comments()
    {
        var model=GitReview.Fixtures.PanelFixtures.NoReviewReady();
        Assert.DoesNotContain(PanelLayoutBuilder.PanelLayout(model).Blocks.OfType<Block.ToolsSection>(),b=>b.Title==CommentsCopy.title);
        var report=Comments.Parse("comments-diagnostic\t\tread\tCannot read comments");
        var section=PanelLayoutBuilder.PanelLayout(model with {Comments=report}).Blocks.OfType<Block.ToolsSection>().Single(b=>b.Title==CommentsCopy.title);
        Assert.Empty(section.NestedBlocks.OfType<Block.GuideRows>());
        Assert.Equal("Cannot read comments",Assert.Single(section.NestedBlocks.OfType<Block.Stderr>()).Text);
    }
    [Fact] public void Capture_destinations_come_only_from_CLI_capabilities()
    {
        var report=Comments.Parse("comments-capability\tinit\tlocal\ncomments-capability\tadd\tshared\ncomments-capability\tadd\tshared\ncomments-capability\tadd\tunknown\ncomments-capability\tadd\ncomments-context\tc\tcompare\tactive\tg\tCompare");
        Assert.Equal(new[]{"shared"},report.Destinations());
        Assert.Empty(Comments.Parse("comments-guard\tg").Destinations());
    }
    [Fact] public void Exact_selection_round_trips_UTF16_endpoints_and_legacy_ranges()
    {
        const string text="a😀\tZ\nlast";
        Assert.Equal((1,2,2,1),Comments.SelectionCoordinates(1,0,0,1));
        var report=Comments.Parse("comment-entry\t1\t1\t1\tfile\ncomment-scope\t1\tselection\thead\ncomment-path\t1\thead\tfile\ncomment-location\t1\thead\t1\t2\ncomment-columns\t1\thead\t2\t1");
        Assert.Equal("file:1:2–2:1 · New version",CommentPresentations.Present(report,report.Records("comment-entry").Single()).Location);
        var columns=report.Records("comment-columns").Single();
        var offsets=Comments.TextOffsets(text,1,2,int.Parse(columns[2]),int.Parse(columns[3]));
        Assert.Equal("😀\tZ\n",text.Substring(offsets.Start,offsets.End-offsets.Start));
        Assert.Equal((1,3),Comments.TextOffsets(text,1,1,2,4));
        Assert.Equal((0,5),Comments.TextOffsets(text,1,1));
        Assert.Throws<InvalidOperationException>(()=>Comments.TextOffsets(text,1,1,2,9));
        Assert.Throws<InvalidOperationException>(()=>Comments.TextOffsets(text,1,1,2));
    }
    [Fact] public void Watchers_use_reported_document_parents_and_exact_saves()
    {
        var state=new ReviewState(Situation.Review,Comments:Comments.Parse("comments-document\t/git/session/local.md\tc\tlocal\tabsent\tabsent\ncomments-document\t/git/result/shared.md\tc\tshared\tpresent\tr"));
        Assert.Equal(new[]{"/git/result","/git/session"},DraftWatch.WatchDirs(state));
        Assert.True(DraftWatch.IsReportedGuide(state,"/git/session/local.md"));
        Assert.False(DraftWatch.IsReportedGuide(state,"/git/session/other.md"));
        Assert.Empty(DraftWatch.WatchDirs(new ReviewState(Situation.Review)));
    }
    [Fact] public void Results_follow_walkthrough_and_keep_local_and_shared_controls_independent()
    {
        const string wire="comments-context\tc\treview\tresult\tg\tFeature\ncomments-document\t/l\tc\tlocal\tpresent\tl\ncomments-document\t/s\tc\tshared\tabsent\tabsent\ncomments-delivery\tc\tpending\tDestination changed";
        var model=GitReview.Fixtures.PanelFixtures.NoReviewReady() with {Comments=Comments.Parse(wire)};
        var layout=PanelLayoutBuilder.PanelLayout(model);
        var sections=layout.Blocks.OfType<Block.ToolsSection>().Select(b=>b.Title).ToList();
        Assert.True(sections.IndexOf(CommentsCopy.title)>sections.IndexOf("Walkthrough"));
        Assert.True(sections.IndexOf(CommentsCopy.title)<sections.IndexOf("Compare"));
        var controls=layout.CollectControls();
        Assert.Single(controls,c=>c.Id==ControlId.OpenComments);
        Assert.Single(controls,c=>c.Id==ControlId.DeleteComments);
        Assert.Single(controls,c=>c.Id==ControlId.PrepareSharedComments);
        Assert.DoesNotContain(controls,c=>c.Id==ControlId.AddComment);
    }
    [Fact] public void Repository_shared_has_only_reading_controls_outside_review()
    {
        var report=Comments.Parse("comments-context\tc\treview\trepository\tg\tFeature\ncomments-document\t/repo/.review/comments.md\tc\tshared\tpresent\ts");
        var layout=PanelLayoutBuilder.PanelLayout(GitReview.Fixtures.PanelFixtures.NoReviewReady() with {Comments=report});
        var controls=layout.CollectControls();
        Assert.Contains(controls,c=>c.Id==ControlId.OpenComments);
        Assert.Contains(controls,c=>c.Id==ControlId.OpenCommentDiff);
        Assert.DoesNotContain(controls,c=>c.Id==ControlId.AddComment || c.Id==ControlId.DeleteComments || c.Id==ControlId.RenumberComments);
    }
    [Fact] public void Shared_fixture_covers_every_record_and_exact_custody()
    {
        var root=new DirectoryInfo(AppContext.BaseDirectory);
        while(root is not null && !File.Exists(Path.Combine(root.FullName,"tests/fixtures/comments/client-records.tsv")))root=root.Parent;
        Assert.NotNull(root);
        var report=Comments.Parse(File.ReadAllText(Path.Combine(root!.FullName,"tests/fixtures/comments/client-records.tsv")));
        Assert.Equal(4,report.Documents.Count);Assert.Null(report.Documents[0].Count);Assert.Equal(0,report.Documents[1].Count);
        var tags=report.Rows.Select(r=>r.Tag).ToHashSet();
        foreach(var tag in new[]{"comments-owner","comments-context","comments-guard","comments-document","comments-count","comments-diagnostic","comments-identity","comments-candidate","comments-delivery","comments-capture","comment-entry","comment-body","comment-scope","comment-version","comment-path","comment-location","comment-unversioned","comment-diagnostic","comment-diff","comment-blob","comments-delivery-file"})Assert.Contains(tag,tags);
        Assert.DoesNotContain("future-tag",tags);
        Assert.Equal(new[]{"/private/local.md","/private/shared.md"},Comments.OwnedBy(report,new[]{"review/feature/comments"}).Select(d=>d.Path));
        Assert.Empty(Comments.OwnedBy(report,new[]{"review/other"}));
        Assert.Equal("old%2525name",report.Records("comment-path").Single()[2]);
    }
    private const string Wire = "comments-guard\tstep1\ncomments-context\tc1\treview\tactive\tstep1\tFeature\ncomments-context\tc2\tcompare\tresult\tg2\tOther\ncomments-document\t/l\tc1\tlocal\tpresent\tunreadable\ncomments-document\t/s\tc1\tshared\tabsent\tabsent\textra\ncomments-diagnostic\t/l\tread\tCannot read\ncomments-count\t/s\t0\ncomments-count\t/l\tbad\ncomments-delivery\tc1\tpending\tChanged\nfuture-tag\tignored";
    [Fact] public void Documents_stay_independent_and_unreadable_is_not_zero()
    {
        var report = Comments.Parse(Wire);
        Assert.Equal("step1", report.Guard);
        Assert.Equal(new[]{"c1", "c2"}, report.Records("comments-context").Select(f => f[0]));
        Assert.Equal(new[]{"local", "shared"}, report.Documents.Select(d => d.Kind));
        Assert.Null(report.Documents[0].Count);
        Assert.Equal(0, report.Documents[1].Count);
        Assert.Equal("unreadable", report.Documents[0].Revision);
        Assert.Equal("pending", report.Records("comments-delivery").Single()[1]);
    }
    [Fact] public void Physical_ordinal_is_independent_of_visible_number()
    {
        var report = Comments.Parse("comment-entry\t2\t7\t12\tSecond\ncomment-entry\t1\t7\t2\tFirst\ncomment-diff\t2\tB1\tH1\ncomment-blob\told\tbase\tpresent\tblob1\ncomment-blob\tnew\thead\tabsent");
        Assert.Equal(new[]{"2", "1"}, report.Records("comment-entry").Select(f => f[0]));
        Assert.Equal(new[]{"2", "B1", "H1"}, report.Records("comment-diff").Single());
        Assert.Equal("absent", report.Records("comment-blob").Last()[2]);
    }
}
