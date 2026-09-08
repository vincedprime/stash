#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p .build
sources=(Sources/Stash/*.swift)
sources=(${sources:#Sources/Stash/main.swift})
swiftc -parse-as-library -default-isolation MainActor -target arm64-apple-macosx15.0 \
  "${sources[@]}" scripts/check-regressions.swift -lsqlite3 -o .build/stash-regressions
.build/stash-regressions "$@"
