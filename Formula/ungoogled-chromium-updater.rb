class UngoogledChromiumUpdater < Formula
  desc "Menu-bar auto-updater for ungoogled-chromium (SwiftBar plugin + Homebrew)"
  homepage "https://github.com/anttironty/homebrew-ungoogled-chromium-updater"
  url "https://github.com/anttironty/homebrew-ungoogled-chromium-updater/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "235798a4d96264ba01d1103a8444cd1281476c40878d2737592e88da77d1a54b"
  version "0.1.0"
  license "MIT"
  head "https://github.com/anttironty/homebrew-ungoogled-chromium-updater.git", branch: "master"

  depends_on cask: "swiftbar"
  depends_on :macos

  def install
    pkgshare.install "plugins/ungoogled-chromium.3h.sh"
    bin.install "bin/ungoogled-chromium-updater"
  end

  def caveats
    <<~EOS
      One more step to put the updater in your menu bar:

        ungoogled-chromium-updater setup

      This links the plugin into SwiftBar and launches it. The menu-bar icon
      checks for ungoogled-chromium updates every 3 hours; click it to install
      or update on demand. If Chromium isn't installed yet, the menu offers to
      install it for you.

      To remove just this plugin (keeping SwiftBar):

        ungoogled-chromium-updater uninstall
    EOS
  end

  test do
    # The plugin must render a SwiftBar menu (first line is the status icon).
    output = shell_output("#{pkgshare}/ungoogled-chromium.3h.sh")
    assert_match(/^:.*:/, output.lines.first)
  end
end
