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
      sha256 "da6ad679331ce014f75d24a70649f99122933cdb9947854c8f7fa83c2f53f418"
    end
    on_intel do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.1.0/git-review-ui_0.1.0_darwin_amd64.tar.gz"
      sha256 "e2a01133b752e084064058d149f84940ca48568740392ae4082686111193bcae"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.1.0/git-review-ui_0.1.0_linux_arm64.tar.gz"
      sha256 "c6018f7c3015ab33bf4d51e2c9b0e2a1124fc889304f42a882d3dafc83f67291"
    end
    on_intel do
      url "https://github.com/EzeVillo/git-review-workflow/releases/download/tui-v0.1.0/git-review-ui_0.1.0_linux_amd64.tar.gz"
      sha256 "c6af69af08ca340e616ad9152cd242c892812f41dfeee0f5b9849a21fdae03bb"
    end
  end

  depends_on "git"

  def install
    bin.install "git-review-ui"
  end
end
