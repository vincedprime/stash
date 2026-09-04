#!/bin/zsh
set -euo pipefail

app_path=""
for candidate in "/Applications/Stash.app" "$HOME/Applications/Stash.app"; do
  if [[ -d "$candidate" ]]; then
    app_path="$candidate"
    break
  fi
done

if [[ -z "$app_path" ]]; then
  echo "Stash.app was not found in /Applications or $HOME/Applications." >&2
  exit 1
fi

bundle_identifier=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist")
agent_label="${bundle_identifier}.login-item"
agent_dir="$HOME/Library/LaunchAgents"
agent_path="$agent_dir/$agent_label.plist"
app_executable="$app_path/Contents/MacOS/Stash"
mkdir -p "$agent_dir"
cat > "$agent_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$agent_label</string>
  <key>ProgramArguments</key><array><string>$app_executable</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)" "$agent_path" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$agent_path"
echo "Stash will launch at login."
