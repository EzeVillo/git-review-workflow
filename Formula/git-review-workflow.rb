# Homebrew formula for git-review-workflow.
#
# Until a tagged release exists this is a HEAD-only formula — install the tip of
# the default branch with:
#
#     brew install --HEAD EzeVillo/git-review-workflow/git-review-workflow
#
# (requires `brew tap EzeVillo/git-review-workflow https://github.com/EzeVillo/git-review-workflow`)
#
# Once you cut a release, add a stable `url`/`sha256` pair, e.g.:
#
#     url "https://github.com/EzeVillo/git-review-workflow/archive/refs/tags/v0.1.0.tar.gz"
#     sha256 "<shasum -a 256 of the tarball>"
#
class GitReviewWorkflow < Formula
  desc "Git commands to review a pull request branch locally as one staged diff"
  homepage "https://github.com/EzeVillo/git-review-workflow"
  head "https://github.com/EzeVillo/git-review-workflow.git"
  license "MIT"

  depends_on "git"

  def install
    bin.install Dir["bin/git-review-pr", "bin/git-review-next", "bin/git-review-prev",
                    "bin/git-review-status", "bin/git-review-list", "bin/git-review-abort",
                    "bin/git-finish-review", "bin/git-clean-review"]
    bash_completion.install "completions/git-review-workflow.bash"
    zsh_completion.install "completions/git-review-workflow.zsh" => "_git-review-workflow"
    fish_completion.install "completions/git-review-workflow.fish"
  end

  test do
    assert_match "usage: git review-pr", shell_output("#{bin}/git-review-pr --help")
    assert_match "usage: git finish-review", shell_output("#{bin}/git-finish-review --help")
  end
end
