#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$HOME/Applications/Stash.app"
build_dir="$project_dir/.build/arm64-apple-macosx/release"

cd "$project_dir"
swift build -c release
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/Stash" "$app_dir/Contents/MacOS/Stash"
cp "$project_dir/resources/Info.plist" "$app_dir/Contents/Info.plist"
chmod +x "$app_dir/Contents/MacOS/Stash"
echo "Built $app_dir"

