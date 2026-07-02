# Homebrew formula for git-review-workflow.
#
# The `url`/`sha256`/`version` below are kept in sync with the latest tag by the
# release workflow (.github/workflows/release.yml). Until the first `v*` tag is
# cut the stable `url` points at a tag that does not exist yet and `sha256` is a
# placeholder, so install the tip of the default branch instead:
#
#     brew tap EzeVillo/git-review-workflow https://github.com/EzeVillo/git-review-workflow
#     brew install --HEAD EzeVillo/git-review-workflow/git-review-workflow
#
# After a release, the same commands without --HEAD install the tagged version.
class GitReviewWorkflow < Formula
  desc "Git commands to review a pull request branch locally as one staged diff"
  homepage "https://github.com/EzeVillo/git-review-workflow"
  version "0.1.2"
  url "https://github.com/EzeVillo/git-review-workflow/archive/refs/tags/v0.1.2.tar.gz"
  sha256 "fad3eec7e4e1925dbaa985413f0871b96ba8d21e0e2adf2ac34181ebb07a19ff"
  license "MIT"
  head "https://github.com/EzeVillo/git-review-workflow.git"

  depends_on "git"

  def install
    # The dispatcher resolves its own directory and looks for git-review-verbs/
    # and git-review-lib.sh beside it, so keep the three together in libexec and
    # put only the dispatcher on PATH via a symlink. The private verbs directory
    # is never on PATH (git must not discover a verb as `git <verb>`).
    libexec.install "bin/git-review", "bin/git-review-lib.sh", "bin/git-review-verbs"
    bin.install_symlink libexec/"git-review"
    bash_completion.install "completions/git-review-workflow.bash"
    zsh_completion.install "completions/git-review-workflow.zsh" => "_git-review-workflow"
    fish_completion.install "completions/git-review-workflow.fish"
  end

  test do
    assert_match "git review workflow", shell_output("#{bin}/git-review --h")
    assert_match version.to_s, shell_output("#{bin}/git-review --version")
    assert_match "usage: git review start", shell_output("#{bin}/git-review start -h")
    assert_match "usage: git review finish", shell_output("#{bin}/git-review finish -h")
  end
end
