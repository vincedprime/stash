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
- Type in the search field to find copied content or saved tags. Use **Links** or **Colors** to narrow the history.
- Select an item to put it back on the clipboard, then paste into your app with `Command-V`.
- Pin an item to protect it from automatic cleanup.
- Use the pause control in the menu-bar menu when you do not want Stash to record copies.
- Open **Settings…** from the menu-bar menu, the gear button, or `Command-,` while Stash is focused. Storage, auto-delete, and keyboard bindings are configured there; click **Save changes** to apply them.
- To edit text, links, or hex colours, select an entry and click **Edit** below its preview. Use **Save** or **Cancel**; Enter and arrow keys operate inside the editor while editing. Standard macOS copy, paste, selection, undo, and redo work through the Edit menu.
- Click **Add tags**, type comma-separated names such as `work, design`, then click **Save tags** (or press Return). **Edit tags** changes or removes them. The Tags metadata row is hidden when empty.
- Select a supported text or code file to preview its current contents in a monospaced pane. Previews read at most 100 KB plus one byte to detect truncation, preserve indentation, and show a notice for binary, unsupported, or missing files. For a group of files, the first file is previewed. Return still copies the entire file or group; previewing does not edit the source file.
- Restoring an item from Stash does not record it again. Consecutive copies of the same file group from another app update its copy count instead of adding another entry. Existing duplicate history entries are left intact.
- Delete individual items or choose **Clear All** in the history panel. Clear All asks for confirmation before permanently deleting all entries, including pinned items; choose **Cancel** to keep them.

## Storage and limits

- Stash saves its database and image files at `~/Library/Application Support/Stash`.
- Text, HTTP/HTTPS links, PNG-normalized images, local file references, native colours, and hex colour literals are supported. File contents are not backed up; the original files must still exist when pasted.
- Hex detection accepts `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, and six hexadecimal digits such as `F7ADAD`. It checks only a whole literal; a sentence containing a colour stays text. Link classification checks whole URLs up to 4 KB. No language detection or full-document analysis runs.
- The default cap is 50 MB. Settings offers 25, 50, 100, or 250 MB.
- When space runs low, Stash removes the oldest unpinned entries first. If pinned entries fill the cap, recording pauses until space is freed.
- Auto-delete defaults to **Never**. Options are one hour, one day, or one week since the entry's most recent copy. Cleanup runs at launch, when history opens, and roughly once a minute while Stash runs, including when recording is paused. Sleep/quit delays cleanup until Stash resumes. Pinned items are excluded.
- Saving a shorter retention duration or lower storage limit can remove eligible unpinned entries immediately. **Clear All** also removes pinned entries; **Delete recent** preserves them.

## Keeping Stash lightweight

- History opens with 100 entries and loads another batch when you scroll or navigate past the loaded rows. Each list entry contains at most 360 characters of text; search still matches the entire stored content and tags.
- The inspector shows up to 16,000 characters. A notice identifies shortened previews. Restoring an entry always copies its full stored content. **Edit** loads the full text on demand into a native editor, with layout limited to needed regions and no full-text SwiftUI update on each keystroke.
- Image thumbnails are downsampled to at most 64 pixels on their longest side; inspector previews use at most 1,024 pixels. This also applies to older images without saved thumbnails. The cache retains at most 8 MiB of decoded pixels and 128 images. This is a cache limit, not a limit on the app's total memory. Restoring an image uses its original stored resolution.
- Closing history clears loaded entries, previews, pending searches, and editor state. Clipboard capture and automatic cleanup continue while the panel is closed.
- Large image capture, full-text searches, and explicitly opening a very large item for editing can still require more processing or memory. These changes do not add background content analysis or network activity.

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
defaults delete com.vinylstack.stash 2>/dev/null || true
```

## Development

Build the project without installing the app:

```sh
swift build
```

Some managed Macs do not include XCTest or Swift Testing. An SDK-only regression runner uses temporary data and a private pasteboard. It checks classification, persisted edits/tags, retention, migration, paginated navigation, full-content restore/editing behind shortened previews, image cache limits, and closing/reopening history:

```sh
zsh scripts/check-regressions.sh
```
