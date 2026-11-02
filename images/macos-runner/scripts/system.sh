#!/bin/bash
set -euo pipefail

cat >/Library/LaunchDaemons/limit.maxfiles.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>limit.maxfiles</string>
  <key>ProgramArguments</key>
  <array>
    <string>launchctl</string>
    <string>limit</string>
    <string>maxfiles</string>
    <string>524288</string>
    <string>524288</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
chown root:wheel /Library/LaunchDaemons/limit.maxfiles.plist
chmod 0644 /Library/LaunchDaemons/limit.maxfiles.plist

mdutil -a -i off
softwareupdate --install-rosetta --agree-to-license
ln -sfn "/Users/$SUDO_USER" /Users/runner
