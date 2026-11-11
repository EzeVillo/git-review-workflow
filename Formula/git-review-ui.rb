# Homebrew formula for the terminal git review client. release-tui.yml pins
# the version, URLs and checksums after publishing the release assets.
class GitReviewUi < Formula
  desc "Terminal interface for the git review workflow"
  homepage "https://git-review.ezevillo.com/"
  version "0.2.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.2.0/git-review-ui_0.2.0_darwin_arm64.tar.gz"
      sha256 "b91f76be18da08e7ecb8f89a63e49305a0e76284f97f417f26bc52c17098e244"
    end
    on_intel do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.2.0/git-review-ui_0.2.0_darwin_amd64.tar.gz"
      sha256 "fb69f1ea9554974667637684920a3ee87571b5e7239d2fcd26cd6532f9cc2cc1"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.2.0/git-review-ui_0.2.0_linux_arm64.tar.gz"
      sha256 "66a65fb1661725c9c3b0c1b069709f3d9264c74dad3028b250728d77e458b2e3"
    end
    on_intel do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.2.0/git-review-ui_0.2.0_linux_amd64.tar.gz"
      sha256 "87100f2138bffd6d5a315e8d01bcbbd5f1fc19c49fe4757f5036f5f4ab1c3a1f"
    end
  end

  depends_on "git"

  def install
    bin.install "git-review-ui"
  end
end
