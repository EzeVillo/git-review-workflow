using Xunit;

namespace GitReview.Domain.Tests;

public class VersionTests
{
    [Fact]
    public void Compare_equal()
    {
        Assert.Equal(0, CliVersion.CompareVersions("0.4.0", "0.4.0"));
    }

    [Fact]
    public void Compare_major_minor_patch()
    {
        Assert.True(CliVersion.CompareVersions("0.4.0", "1.0.0") < 0);
        Assert.True(CliVersion.CompareVersions("0.3.9", "0.4.0") < 0);
        Assert.True(CliVersion.CompareVersions("0.4.0", "0.4.1") < 0);
        Assert.True(CliVersion.CompareVersions("0.5.0", "0.4.0") > 0);
        // Numeric, not lexicographic: 0.10.0 is newer than 0.9.0.
        Assert.True(CliVersion.CompareVersions("0.10.0", "0.9.0") > 0);
        Assert.True(CliVersion.CompareVersions("2.0.0", "10.0.0") < 0);
    }

    [Fact]
    public void Invalid_format_returns_null()
    {
        Assert.Null(CliVersion.CompareVersions("not-a-version", "0.4.0"));
        Assert.Null(CliVersion.CompareVersions("0.4", "0.4.0"));
        Assert.Null(CliVersion.CompareVersions("0.4.0.1", "0.4.0"));
        Assert.Null(CliVersion.CompareVersions("-1.0.0", "0.4.0"));
        Assert.Null(CliVersion.CompareVersions("", "0.4.0"));
    }

    [Fact]
    public void Surrounding_whitespace_is_tolerated()
    {
        Assert.Equal(0, CliVersion.CompareVersions(" 0.6.0 ", "0.6.0"));
        Assert.False(CliVersion.IsOutdated(" 0.6.0\n"));
    }

    [Fact]
    public void Is_outdated_against_min()
    {
        Assert.Equal("0.6.0", CliVersion.MinCliVersion);
        Assert.False(CliVersion.IsOutdated(CliVersion.MinCliVersion));
        foreach (var older in new[] { "0.2.1", "0.3.0", "0.3.9", "0.4.0", "0.4.9", "0.5.0", "0.5.9" })
            Assert.True(CliVersion.IsOutdated(older), $"{older} is older than the minimum");
        foreach (var newer in new[] { "0.6.1", "0.7.0", "1.0.0", "10.0.0" })
            Assert.False(CliVersion.IsOutdated(newer), $"{newer} is not older than the minimum");
    }

    /// <summary>
    /// A version string the client cannot read counts as outdated: the panel then
    /// offers the update, which is the recoverable side of the guess.
    /// </summary>
    [Fact]
    public void Unreadable_versions_count_as_outdated()
    {
        Assert.True(CliVersion.IsOutdated("garbage"));
        Assert.True(CliVersion.IsOutdated(""));
        Assert.True(CliVersion.IsOutdated("git-review version 0.6.0"));
    }
}
