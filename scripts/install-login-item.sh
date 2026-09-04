#!/bin/zsh
set -euo pipefail

agent_dir="$HOME/Library/LaunchAgents"
agent_path="$agent_dir/com.vinay.stash.plist"
app_executable="$HOME/Applications/Stash.app/Contents/MacOS/Stash"
mkdir -p "$agent_dir"
cat > "$agent_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.vinay.stash</string>
  <key>ProgramArguments</key><array><string>$app_executable</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)" "$agent_path" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$agent_path"
echo "Stash will launch at login."

