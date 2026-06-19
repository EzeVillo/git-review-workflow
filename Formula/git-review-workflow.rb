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
  version "0.0.1"
  url "https://github.com/EzeVillo/git-review-workflow/archive/refs/tags/v0.0.1.tar.gz"
  sha256 "c3dc344693d7b4a7aa649b757b9ed7f4aa5cd5148bb0af0f0620f57b8fc83295"
  license "MIT"
  head "https://github.com/EzeVillo/git-review-workflow.git"

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
