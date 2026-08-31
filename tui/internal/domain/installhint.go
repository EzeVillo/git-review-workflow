package domain

// NpmInstallCmd / NpmUpdateCmd are the CLI's own npm commands — what draws
// the cli-missing / cli-outdated panels. The TUI itself is never installed
// through npm (FR-049); these two strings exist only because the CLI is.
const (
	NpmInstallCmd = "npm install -g git-review-workflow"
	NpmUpdateCmd  = "npm install -g git-review-workflow@latest"
)

// CliInstallKind selects which of the two commands applies.
type CliInstallKind int

const (
	CliInstall CliInstallKind = iota
	CliUpdate
)

// NpmCommandFor returns the CLI install command for the given kind.
func NpmCommandFor(kind CliInstallKind) string {
	if kind == CliUpdate {
		return NpmUpdateCmd
	}
	return NpmInstallCmd
}
