# The formula a homebrew-pidly tap would carry (53). It is kept here, beside
# the script, so that publishing is copying a file rather than writing one.
#
# The version is in the url and must match VERSION in bin/pidly, which
# tests/packaging.sh checks. The sha256 cannot be real until the tag is
# pushed; the README's release steps say how to fill it in.
class Pidly < Formula
  desc "File-based issue tracker that needs no server or database"
  homepage "https://github.com/ShannonTully/pidly"
  url "https://github.com/ShannonTully/pidly/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "UNRELEASED"
  license "MIT"

  def install
    bin.install "bin/pidly"
    man1.install "docs/pidly.1"
  end

  test do
    assert_equal "pidly #{version}", shell_output("#{bin}/pidly --version").strip
    system bin/"pidly", "init"
    assert_predicate testpath/".pidly/schema", :exist?
  end
end
