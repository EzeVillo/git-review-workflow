# Homebrew formula for the terminal git review client. The version is stamped
# before tagging; release-tui.yml replaces the placeholder checksums after the
# seven assets have been built and published.
class GitReviewUi < Formula
  desc "Terminal interface for the git review workflow"
  homepage "https://github.com/EzeVillo/git-review-workflow"
  version "0.1.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.1.0/git-review-ui_0.1.0_darwin_arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
    on_intel do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.1.0/git-review-ui_0.1.0_darwin_amd64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.1.0/git-review-ui_0.1.0_linux_arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
    on_intel do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.1.0/git-review-ui_0.1.0_linux_amd64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  depends_on "git"

  def install
    bin.install "git-review-ui"
  end
end
