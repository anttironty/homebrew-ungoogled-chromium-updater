# ungoogled-chromium-updater

Simply **keep [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium) up to date on macOS** — with a menu-bar icon that tells you when an update is available and updates it in one click. If Chromium isn't installed yet, it can install it for you too.

## Install

```sh
brew install anttironty/ungoogled-chromium-updater/ungoogled-chromium-updater
ungoogled-chromium-updater setup
```

That installs SwiftBar (if needed), links the plugin, and launches it. Look for the Chromium status icon in your menu bar.

## Commands

```sh
ungoogled-chromium-updater setup       # wire into SwiftBar (default)
ungoogled-chromium-updater check       # print the menu output once
ungoogled-chromium-updater path        # show the resolved plugin path
ungoogled-chromium-updater uninstall   # remove the plugin (keeps SwiftBar)
```

## Try it without installing (dev)

```sh
./bin/ungoogled-chromium-updater check     # renders the menu against your real brew state
./plugins/ungoogled-chromium.3h.sh         # same thing, directly
```

## Requirements

- macOS 11+ (SwiftBar requirement)
- [Homebrew](https://brew.sh)
