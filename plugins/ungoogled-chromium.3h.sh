#!/bin/bash
#
# <xbar.title>Ungoogled Chromium Updater</xbar.title>
# <xbar.version>v0.1.0</xbar.version>
# <xbar.author>ungoogled-chromium-updater</xbar.author>
# <xbar.desc>Keeps ungoogled-chromium up to date via Homebrew. Shows the current/latest version in the menu bar and updates with one click.</xbar.desc>
# <xbar.dependencies>brew</xbar.dependencies>
# <swiftbar.hideAbout>false</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>false</swiftbar.hideDisablePlugin>
#
# This single script is both the SwiftBar plugin (when run with no arguments,
# it prints the menu) and the action handler (when run with "install" or
# "update", it performs the brew operation in a visible Terminal window).
#
# Distributed as part of the ungoogled-chromium-updater Homebrew tap.

CASK="ungoogled-chromium"
# The Homebrew cask installs the bundle as "Chromium.app" (app name "Chromium").
APP="Chromium.app"
APP_NAME="Chromium"
RELEASES_URL="https://github.com/ungoogled-software/ungoogled-chromium-macos/releases"
API_URL="https://formulae.brew.sh/api/cask/${CASK}.json"

# --- Locate brew (SwiftBar may launch us with a minimal PATH) -----------------
find_brew() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && { echo "$b"; return 0; }
  done
  b="$(command -v brew 2>/dev/null)" && [ -n "$b" ] && { echo "$b"; return 0; }
  return 1
}
BREW="$(find_brew || true)"

notify() { # title, message
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

installed_version() { # echoes version or empty (strips brew's ,timestamp suffix)
  [ -n "$BREW" ] || return 0
  "$BREW" list --cask --versions "$CASK" 2>/dev/null | awk '{print $2}' | cut -d',' -f1
}

latest_version() { # echoes version brew would install, or empty on network failure
  /usr/bin/curl -fsSL --max-time 10 "$API_URL" 2>/dev/null \
    | /usr/bin/sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -1
}

# Returns 0 if $2 (latest) is strictly newer than $1 (installed)
is_newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
}

# =============================================================================
# ACTION MODE — invoked from a menu click with a Terminal window attached.
# =============================================================================
case "${1:-}" in
  install)
    set -uo pipefail
    echo "==> Installing ungoogled-chromium via Homebrew…"
    echo
    "$BREW" install --cask "$CASK"
    rc=$?
    echo
    if [ $rc -eq 0 ]; then
      notify "Ungoogled Chromium" "Installed successfully."
      echo "✅ Done. You can close this window."
    else
      notify "Ungoogled Chromium" "Install failed (see Terminal)."
      echo "❌ Install failed. See the output above."
    fi
    # Ask SwiftBar to refresh this plugin so the menu reflects the new state.
    /usr/bin/open -g "swiftbar://refreshplugin?name=ungoogled-chromium" >/dev/null 2>&1 || true
    exit $rc
    ;;
  update)
    set -uo pipefail
    echo "==> Updating ungoogled-chromium via Homebrew…"
    echo
    # A cask upgrade needs the app closed. Offer to quit it if running.
    if /usr/bin/pgrep -f "/$APP/" >/dev/null 2>&1; then
      echo "Ungoogled Chromium is currently running and must be quit to update."
      printf "Quit it now and continue? [y/N] "
      read -r ans
      case "$ans" in
        y|Y) /usr/bin/osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true; sleep 2 ;;
        *)   echo "Aborted. Nothing was changed."; exit 1 ;;
      esac
    fi
    "$BREW" upgrade --cask "$CASK"
    rc=$?
    if [ $rc -ne 0 ]; then
      # A failed upgrade can leave the app removed but not replaced (e.g. drifted
      # Caskroom state). Recover with a clean reinstall so we never strand the user.
      echo
      echo "⚠️  Upgrade failed; attempting a clean reinstall to recover…"
      "$BREW" reinstall --cask "$CASK"
      rc=$?
    fi
    echo
    if [ $rc -eq 0 ]; then
      notify "Ungoogled Chromium" "Updated to the latest version."
      echo "✅ Updated. You can close this window."
    else
      notify "Ungoogled Chromium" "Update failed (see Terminal)."
      echo "❌ Update failed. See the output above."
    fi
    /usr/bin/open -g "swiftbar://refreshplugin?name=ungoogled-chromium" >/dev/null 2>&1 || true
    exit $rc
    ;;
esac

# =============================================================================
# RENDER MODE — no arguments: print the SwiftBar menu.
# =============================================================================
SELF="$0"

# --- brew missing -------------------------------------------------------------
if [ -z "$BREW" ]; then
  echo ":exclamationmark.triangle.fill: | sfcolor=#e0a800"
  echo "---"
  echo "Homebrew not found | color=red"
  echo "This updater needs Homebrew to run. | size=11"
  echo "Install Homebrew… | href=https://brew.sh"
  exit 0
fi

INSTALLED="$(installed_version)"
LATEST="$(latest_version)"

# --- Chromium not installed ---------------------------------------------------
if [ -z "$INSTALLED" ]; then
  echo ":questionmark.circle: | sfcolor=#888888"
  echo "---"
  echo "Ungoogled Chromium is not installed | size=12"
  if [ -n "$LATEST" ]; then
    echo "Latest available: $LATEST | size=11 color=#888888"
  fi
  echo "---"
  echo "Install Ungoogled Chromium | bash=\"$SELF\" param1=install terminal=true refresh=true sfimage=arrow.down.circle"
  echo "---"
  echo "Check again | refresh=true sfimage=arrow.clockwise"
  echo "Releases on GitHub… | href=$RELEASES_URL"
  exit 0
fi

# --- Network/API failure (installed, but couldn't read latest) ----------------
if [ -z "$LATEST" ]; then
  echo ":checkmark.seal: | sfcolor=#888888"
  echo "---"
  echo "Installed: $INSTALLED | size=12"
  echo "Couldn't check for updates (offline?) | size=11 color=#888888"
  echo "---"
  echo "Check now | refresh=true sfimage=arrow.clockwise"
  echo "Releases on GitHub… | href=$RELEASES_URL"
  exit 0
fi

# --- Update available ---------------------------------------------------------
if is_newer "$INSTALLED" "$LATEST"; then
  echo ":arrow.down.circle.fill: | sfcolor=#1e8fff"
  echo "---"
  echo "Update available | size=12 color=#1e8fff"
  echo "$INSTALLED → $LATEST | size=11"
  echo "---"
  echo "Update now | bash=\"$SELF\" param1=update terminal=true refresh=true sfimage=arrow.down.circle.fill"
  echo "---"
  echo "Release notes… | href=$RELEASES_URL"
  echo "Check now | refresh=true sfimage=arrow.clockwise"
  exit 0
fi

# --- Up to date ---------------------------------------------------------------
echo ":checkmark.seal.fill: | sfcolor=#34c759"
echo "---"
echo "Up to date | size=12 color=#34c759"
echo "Installed: $INSTALLED | size=11"
echo "---"
echo "Check now | refresh=true sfimage=arrow.clockwise"
echo "Releases on GitHub… | href=$RELEASES_URL"
