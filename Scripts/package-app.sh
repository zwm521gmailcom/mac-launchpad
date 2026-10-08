#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="MacLaunchpad.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MacLaunchpad "$APP/Contents/MacOS/MacLaunchpad"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacLaunchpad</string>
  <key>CFBundleIdentifier</key>
  <string>local.maclaunchpad</string>
  <key>CFBundleName</key>
  <string>MacLaunchpad</string>
  <key>CFBundleDisplayName</key>
  <string>程序启动台</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
echo "built $APP"
