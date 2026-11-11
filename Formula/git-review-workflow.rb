# Homebrew formula for git-review-workflow.
#
# The release workflow (.github/workflows/release.yml) pins the version, URL
# and SHA-256 together after publishing the release.
class GitReviewWorkflow < Formula
  desc "Git commands to review a pull request branch locally as one staged diff"
  homepage "https://git-review.ezevillo.com/"
  version "0.10.0"
  url "https://github.com/EzeVillo/git-review-workflow/archive/refs/tags/v0.10.0.tar.gz"
  sha256 "4c68b0cf415dcdb9fb1b031c78ea115d109e915b6575f4b8c276eeb95f33aec8"
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
