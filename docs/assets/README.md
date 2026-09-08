# Feature screenshots

These PNGs are rendered from Stash's shipping SwiftUI/AppKit views using isolated
sample data. No personal history, system clipboard content, or external images
are used. The landscape is a small original vector illustration drawn by the
renderer for the image entry.

Regenerate on an Apple Silicon Mac with the project's Swift toolchain:

```sh
zsh scripts/render-site-images.sh
```

The renderer uses light appearance and offscreen bitmap snapshots of native
views. Tahoe's live glass compositing can differ. It uses a temporary database, files, and preferences and removes them
after rendering. It does not install, restart, or change the running app.

Review all four images after regeneration, especially text wrapping, selected
rows, image/code previews, and settings. The site links each screenshot to its
full-size PNG. Keep HTML width/height attributes aligned with the generated sizes.
