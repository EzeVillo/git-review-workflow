using Xunit;

namespace GitReview.Domain.Tests;

public class CompareDraftTests
{
    [Fact]
    public void Comparison_draft_keeps_its_identity_and_starts_compare()
    {
        const string id = "compare/0123456789012345678901234567890123456789";
        var row = $"draft\t{id}\t/repo/.git/order.md\t2\t2\tcompare\tfull\tfresh";
        var title = $"draft-title\t{id}\tmain → release";
        foreach (var text in new[] { row + "\n" + title, title + "\n" + row })
        {
            var draft = Assert.Single(ConfigPorcelain.ParseConfigPorcelain(text).Drafts!);
            Assert.Equal(id, draft.Src);
            Assert.Equal("main → release", draft.Title);
            Assert.Equal(DraftSource.Compare, draft.Source);
            Assert.Equal(new[] { "draft", "--build", "--compare", "--", id }, ReviewIntentLogic.DraftArgs(id, ReviewSource.Compare, ReviewRange.Full, true));
            Assert.Equal(new[] { "--porcelain", "--compare", "--", id }, ReviewIntentLogic.DraftConfigArgs(id, ReviewSource.Compare, ReviewRange.Full));
            var intent = new ReviewIntent(id, ReviewLayout.Keys, ReviewRange.Full, ReviewSource.Compare);
            var argv = ActionArgvMap.ActionToArgv("startReview", new ActionParams.Start(intent, "main"));
            Assert.Equal("compare", argv.Verb);
            Assert.Equal(new[] { "--keys", "--draft", "--", id }, argv.Args);
            Assert.False(argv.Network);
            var model = PanelModelBuilder.BuildPanelModel(new ReviewState(Situation.NoReview, Config: new EffectiveConfig(null, "origin"), Drafts: new[] { draft }), new PanelInputs(false));
            Assert.True(model.NoBaseConfigured);
            var layout = PanelLayoutBuilder.PanelLayout(model);
            Assert.Contains(layout.CollectControls(), c => c.Id == ControlId.StartFromDraft && c.Enabled);
            Assert.Contains(layout.CollectControls(), c => c.Id == ControlId.CompareReview && c.Enabled);
            Assert.Equal("main → release", Assert.Single(Assert.Single(layout.Blocks.OfType<Block.DraftRows>()).Rows).Name);
        }
    }
}
