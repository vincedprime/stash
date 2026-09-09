#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p .build docs/assets
sources=(Sources/Stash/*.swift)
sources=(${sources:#Sources/Stash/main.swift})
swiftc -parse-as-library -default-isolation MainActor -target arm64-apple-macosx15.0 \
  "${sources[@]}" scripts/render-site-images.swift -lsqlite3 -o .build/stash-site-images
.build/stash-site-images "$project_dir/docs/assets"
