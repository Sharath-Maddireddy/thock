#!/bin/sh
# Builds Thock.app and installs it to /Applications.
set -e
cd "$(dirname "$0")"
APP=Thock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/Thock"
mkdir -p "$APP/Contents/Resources" && cp -R sounds Thock.icns "$APP/Contents/Resources/"
"$APP/Contents/MacOS/Thock" --selftest "$APP/Contents/Resources/sounds"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.thock</string>
  <key>CFBundleName</key><string>Thock</string>
  <key>CFBundleExecutable</key><string>Thock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleIconFile</key><string>Thock</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
# Pin the signing requirement to the bundle id so Input Monitoring survives rebuilds.
codesign --force -s - -r='designated => identifier "local.thock"' "$APP"

rm -rf /Applications/"$APP"
cp -R "$APP" /Applications/
echo "Installed /Applications/$APP"
