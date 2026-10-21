using Xunit;
namespace GitReview.Domain.Tests;
public class ComparisonTests
{
    [Theory]
    [InlineData("whole")]
    [InlineData("walk")]
    [InlineData("step")]
    public void Pinned_endpoints_survive_every_model_projection(string mode)
    {
        var p = Porcelain.ParsePorcelain(string.Join("\n",
            $"state\treview/f\tf\t{new string('2', 40)}\t{mode}\tnone\t1\t1\t1\tapp.txt\t0",
            "comparison-target\trefs/remotes/upstream/f",
            $"comparison\t{new string('1', 40)}\t{new string('2', 40)}",
            "comparison-base\trefs/heads/main"));
        var m = PanelModelBuilder.BuildPanelModel(new ReviewState(Situation.Review, State: p.State, Comparison: p.Comparison), new PanelInputs(false));
        Assert.NotNull(m.Comparison);
        Assert.Equal(new[] { "Base: main (1111111)", "Inspect: upstream/f (2222222)" }, UserCopy.ComparisonLines(m.Comparison!));
    }
}
