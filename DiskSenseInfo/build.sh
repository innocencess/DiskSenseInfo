#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/arm64 build/x86_64 dist/DiskSenseInfo.app/Contents/MacOS dist/DiskSenseInfo.app/Contents/Resources
sdk="$(xcrun --sdk macosx --show-sdk-path)"
for arch in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target "$arch-apple-macosx13.0" -module-name DiskSenseInfo Sources/*.swift -o "build/$arch/DiskSenseInfo" -framework SwiftUI -framework Charts -framework AppKit -framework IOKit -framework DiskArbitration -framework ServiceManagement -framework UserNotifications
 done
lipo -create build/arm64/DiskSenseInfo build/x86_64/DiskSenseInfo -output dist/DiskSenseInfo.app/Contents/MacOS/DiskSenseInfo
cp Info.plist dist/DiskSenseInfo.app/Contents/Info.plist
cp Resources/* dist/DiskSenseInfo.app/Contents/Resources/
chmod 755 dist/DiskSenseInfo.app/Contents/Resources/smartctl
codesign --force --sign - dist/DiskSenseInfo.app/Contents/Resources/smartctl
codesign --force --sign - dist/DiskSenseInfo.app
codesign --verify --deep --strict dist/DiskSenseInfo.app
if [[ "${1:-}" == "--dmg" ]]; then
    mkdir -p build/dmg
    ditto dist/DiskSenseInfo.app build/dmg/DiskSenseInfo.app
    ln -sfn /Applications build/dmg/Applications
    hdiutil create -volname DiskSenseInfo -srcfolder build/dmg -ov -format UDZO dist/DiskSenseInfo.dmg
fi
