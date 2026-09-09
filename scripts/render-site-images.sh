#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p .build docs/assets
sources=(Sources/Stash/*.swift)
sources=(${sources:#Sources/Stash/main.swift})
sources=(${sources:#Sources/Stash/NativeAppearance.swift})
# Bitmap snapshots cannot capture WindowServer's glass compositing. Use the
# app's existing bordered-control fallback in this isolated screenshot build.
# The shipping source and installed app are never modified.
appearance_dir=$(mktemp -d .build/site-images.XXXXXX)
appearance_source="$appearance_dir/NativeAppearance.swift"
trap 'rm -f "$appearance_source"; rmdir "$appearance_dir"' EXIT
sed 's/if #available(macOS 26, \*), !reduceTransparency {/if #available(macOS 26, *), false {/' \
  Sources/Stash/NativeAppearance.swift > "$appearance_source"
swiftc -parse-as-library -default-isolation MainActor -target arm64-apple-macosx15.0 \
  "${sources[@]}" "$appearance_source" scripts/render-site-images.swift -lsqlite3 -o .build/stash-site-images
.build/stash-site-images "$project_dir/docs/assets"
