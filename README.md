# Stash

Stash is a native, local-only macOS clipboard manager. It saves text and images copied from the general clipboard on your Mac. It has no account, App Store dependency, cloud sync, network calls, or Accessibility permission requirement.

> Stash records clipboard content from every app. That can include passwords, tokens, and work information. Delete history or pause recording whenever that is not appropriate.

Download the latest release from https://github.com/vincedprime/stash/releases/latest/download/Stash.dmg or visit https://stash.vinyl-stack.com/.

## Install the download

Stash is currently an unsigned build. After downloading and opening `Stash.dmg`, use Terminal to install it instead of dragging it in Finder:

```sh
cp -R "/Volumes/Stash/Stash.app" "/Applications/"
xattr -dr com.apple.quarantine "/Applications/Stash.app"
open "/Applications/Stash.app"
```

This copies Stash to Applications, clears macOS’s download quarantine for this local build, and opens it. If your Mac is managed and blocks the command, its administrator must allow the app.

## Set up locally

### Pre-requisites 

- Apple Silicon Mac running macOS 15 or later.
- Apple Command Line Tools. Check with:

  ```sh
  swift --version
  ```

  If that command is unavailable, install the Command Line Tools from Terminal:

  ```sh
  xcode-select --install
  ```

1. Clone the repository and enter it:

   ```sh
   git clone git@github-vinyl:vincedprime/stash.git
   cd stash
   ```

2. Build and install the menu-bar app:

   ```sh
   zsh scripts/build-app.sh
   ```

   This creates `~/Applications/Stash.app`.

3. Open `Stash.app` from Finder, or run:

   ```sh
   open ~/Applications/Stash.app
   ```

4. Find the archive-box icon in the macOS menu bar. Stash begins recording supported clipboard items as soon as it is open.

5. Optional: start Stash automatically after each login:

   ```sh
   zsh scripts/install-login-item.sh
   ```

## Use Stash

- Click the menu-bar icon or press `Option-Space` to open history.
- Type in the search field to filter copied text.
- Select an item to put it back on the clipboard, then paste into your app with `Command-V`.
- Pin an item to protect it from automatic cleanup.
- Use the pause control in the menu-bar menu when you do not want Stash to record copies.
- Choose **Shortcut: Option-Space** from the menu to switch to `Option-Shift-Space`. Stash remembers the choice.
- Delete individual items or choose **Clear All** in the history panel to immediately remove retained history.

## Storage and limits

- Stash saves its database and image files at `~/Library/Application Support/Stash`.
- Text and PNG-normalized images are supported.
- History is retained until manually deleted, subject to a 50 MB total cap.
- When space runs low, Stash removes the oldest unpinned entries first. If pinned entries fill the cap, recording pauses until space is freed.

## Uninstall

Quit Stash, disable its optional launch agent, and remove both the downloaded and locally built app locations:

```sh
pkill -x Stash 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.vinylstack.stash.login-item.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.vinylstack.stash.login-item.plist"
rm -rf "/Applications/Stash.app" "$HOME/Applications/Stash.app"
```

Clipboard history is kept so it can be restored after reinstalling. To permanently remove all Stash history and settings too:

```sh
rm -rf "$HOME/Library/Application Support/Stash"
defaults delete com.vinay.stash 2>/dev/null || true
```

## Development

Build the project without installing the app:

```sh
swift build
```

The installed Command Line Tools on some managed Macs do not include the XCTest or Swift Testing modules. In that case, `swift build` is the available local validation command.
