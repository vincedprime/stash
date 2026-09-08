# TODO

Reviewed against `main` after the metadata-inspector merge (`49b7367`).

## Open

- [ ] Export and import clipboard history.
- [ ] Skip app builds and DMG releases for documentation-only changes. Keep landing-page deployment enabled.
- [ ] Replace landing-page offscreen renders with actual macOS window screenshots using sample clipboard content.

## Done

- [x] Support links, files, and colours, with corresponding history filters.
- [x] Configure clipboard storage size in Settings.
- [x] Remove the double selection highlight and maintain a valid selection when changing filters. The final selection colour is grey, superseding the earlier blue request.
- [x] Delete all entries, with confirmation before clearing pinned items too.
- [x] Delete recent entries using 5-minute, one-hour, and one-day presets; preserve pinned entries.
- [x] Automatically delete old unpinned entries according to a retention setting.
- [x] Show content type in metadata.
- [x] Edit saved text, links, and colour literals.
- [x] Add/edit tags and include them in search.
- [x] Select and copy text from the preview pane with standard macOS text actions.
- [x] Route selection, cut, copy, paste, undo, and redo through the native Edit menu and text responder; preserve search-field editing shortcuts.
