#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/AppIcon.iconset
swift Artwork/PackageIcon.swift Artwork/AppIcon.png build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
