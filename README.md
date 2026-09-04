# Stash

Stash is a native, local-only macOS clipboard manager. It stores text and images from the general clipboard in `~/Library/Application Support/Stash`, with a 50 MB quota and no network access.

## Use

Run `scripts/build-app.sh` to create `~/Applications/Stash.app`, then open the app. Click the archive-box menu-bar icon or press `Option-Space` to search history. The menu lets you switch to `Option-Shift-Space`; Stash remembers that choice. Choosing an item restores it to the clipboard; paste normally with `Command-V`.

Run `scripts/install-login-item.sh` after building to start Stash automatically after login. To stop that behavior, run `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.vinay.stash.plist` and remove that plist.

Stash never uses Accessibility APIs. It records clipboard text and images from every app, so delete history when you do not want content retained.
