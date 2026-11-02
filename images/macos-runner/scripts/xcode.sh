#!/bin/bash
set -euo pipefail

shared="/Volumes/My Shared Files"
if [ ! -d "$shared" ]; then
  sudo mkdir -p "$shared"
  sudo mount_virtiofs com.apple.virtio-fs.automount "$shared"
fi

selected=""
for app in $XCODE_APPS; do
  archives=("$shared"/*/"$app.tar")
  staging=$(sudo mktemp -d /Applications/.xcode.XXXXXX)
  sudo tar -xf "${archives[0]}" -C "$staging"
  version=$(sudo /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$staging/$app/Contents/Info.plist")
  target="/Applications/Xcode_$version.app"
  sudo mv "$staging/$app" "$target"
  sudo rmdir "$staging"
  selected=${selected:-$target}
done

sudo xcode-select -s "$selected"
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS
xcodebuild -downloadComponent MetalToolchain
xcrun simctl runtime dyld_shared_cache update --all

xcodebuild -version
xcrun simctl list runtimes
