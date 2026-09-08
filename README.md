# Stash

A native macOS clipboard manager.

[Features and screenshots](https://stash.vinyl-stack.com/) · [Install](https://stash.vinyl-stack.com/#install) · [Uninstall](https://stash.vinyl-stack.com/#uninstall)

## Build from source

Requires an Apple Silicon Mac, macOS 15 or later, and Swift 6.2 or later. Install Apple Command Line Tools with `xcode-select --install` if needed; check the toolchain with `swift --version`.

1. Clone the repository:

   ```sh
   git clone https://github.com/vincedprime/stash.git
   cd stash
   ```

2. Build and install to `~/Applications/Stash.app`:

   ```sh
   zsh scripts/build-app.sh
   ```

3. Launch:

   ```sh
   open "$HOME/Applications/Stash.app"
   ```

To update a source installation, quit Stash, pull the latest code, and repeat steps 2–3.

## Launch at login

After installing, run:

```sh
zsh scripts/install-login-item.sh
```

The script finds Stash in `/Applications` or `~/Applications` and registers a user-level LaunchAgent. If both exist, it uses `/Applications`. Registration failures appear in Terminal.

## Usage details

- A single click selects an entry for preview. Double-click or Return restores it and dismisses history.
- Additional defaults: `⌥P` pins/unpins, `⌥X` deletes, `⌥Q` cycles filters, and `⌥R` pauses/resumes recording. Open Settings with `⌘,`. Navigation arrows and Return are fixed; the other history actions and global shortcuts are configurable.
- In the text editor, `⌘S` saves and Escape cancels. Editing affects the stored entry, not the original source document.
- **Add tags** accepts comma-separated names, such as `work, design`. Save with Return or `⌘S`; **Edit tags** also lets you remove them. Search matches stored content and tags.
- **Delete recent** offers the last 5 minutes, hour, or day and preserves pinned entries. **Clear All** asks for confirmation and includes pinned entries.

## Data and limits

- History lives in `~/Library/Application Support/Stash`, using SQLite and separate image files. Preferences use the `com.vinylstack.stash` defaults domain.
- Storage defaults to 50 MB; available limits are 25, 50, 100, and 250 MB. Oldest unpinned entries are evicted first. If an entry cannot fit, Stash skips saving it and shows a storage-full message; normal copying continues.
- Auto-delete defaults to Never, with one-hour, one-day, and one-week options. Age starts at the most recent recorded copy. Cleanup runs at launch, on opening history, and approximately every minute, including while recording is paused. Quit or sleep delays cleanup; pinned entries are excluded. Lowering a limit can delete eligible history immediately.
- Files are references to their original locations, not backups. File previews show current contents, read up to 100 KB, and preview only the first file in a group. Moved, deleted, binary, or unsupported files may not preview.
- Colour text must be a whole `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA` literal. Bare hex stays text. Link detection requires a whole HTTP/HTTPS URL. Classification is limited to entries up to 4 KB.
- Images are stored as PNG. Rich-text formatting and app-private clipboard formats are not preserved.
- The source-app label is the foreground app observed at capture time, not verified provenance. Copies made between clipboard polls may be missed.

## Development

Build without installing, then run the SDK-only regression checks:

```sh
swift build
zsh scripts/check-regressions.sh
```

The runner uses temporary data and a private pasteboard; XCTest and Swift Testing are not required. It covers storage, classification, editing, retention, navigation, preview limits, and clipboard restoration.

History loads in batches of 100 with 360-character list excerpts. Text previews are capped at 16,000 characters; editing and restoration load the full entry. Image previews are downsampled, with an 8 MiB / 128-image cache. Closing history releases loaded views and data. These are working-set controls, not a cap on total app memory.

The landing page is plain HTML, CSS, and JavaScript in [`docs/`](docs/index.html). See the [image capture notes](docs/assets/README.md) before updating its images. The release workflow skips only Markdown-only pushes to `main`. Landing-page HTML, CSS, JavaScript, images, and rendering scripts trigger a build and DMG release, as do app and packaging changes. GitHub Pages deployment remains independent and enabled.

[Outstanding work](docs/todo.md)
