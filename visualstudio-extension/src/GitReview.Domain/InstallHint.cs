namespace GitReview.Domain;

/// <summary>Keep in sync with contracts/client-product-surface.yaml.</summary>
public static class InstallHint
{
    public const string NpmInstallCmd = "npm install -g git-review-workflow";
    public const string NpmUpdateCmd = "npm install -g git-review-workflow@latest";

    public enum CliInstallKind
    {
        Install,
        Update,
    }

    public static string NpmCommandFor(CliInstallKind kind) =>
        kind == CliInstallKind.Update ? NpmUpdateCmd : NpmInstallCmd;
}
