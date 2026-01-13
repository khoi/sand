class Sand < Formula
  desc "Run ephemeral macOS VMs via Tart and provision inside each VM"
  homepage "https://github.com/khoi/sand"
  head "https://github.com/khoi/sand.git", branch: "main"

  depends_on :macos

  def install
    # Avoid requiring SSH credentials during SwiftPM dependency fetches.
    inreplace "Package.swift",
              "git@github.com:apple/swift-log.git",
              "https://github.com/apple/swift-log.git"
    inreplace "Package.resolved",
              "git@github.com:apple/swift-log.git",
              "https://github.com/apple/swift-log.git"

    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/sand"
  end

  test do
    system bin/"sand", "--help"
  end

  def caveats
    <<~EOS
      sand requires macOS 14+ and Tart available in your PATH.
    EOS
  end
end
