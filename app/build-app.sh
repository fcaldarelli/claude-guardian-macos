#!/bin/bash
# Compila l'app e la impacchetta in "build/Claude Guardian.app" (firmata ad-hoc).
# Requisiti: macOS 13+, Xcode o Command Line Tools (xcode-select --install).
set -euo pipefail

cd "$(dirname "$0")"

# La versione è definita nel codice (Sources/ClaudeGuardian/AppInfo.swift):
# qui viene solo letta, per scriverla nell'Info.plist.
INFO_SWIFT="Sources/ClaudeGuardian/AppInfo.swift"
VERSION="$(sed -n 's/^[[:space:]]*static let version = "\([^"]*\)".*/\1/p' "$INFO_SWIFT")"
BUILD="$(sed -n 's/^[[:space:]]*static let build = "\([^"]*\)".*/\1/p' "$INFO_SWIFT")"
if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
  echo "✗ Versione non trovata in $INFO_SWIFT" >&2
  exit 1
fi

swift build -c release

APP="build/Claude Guardian.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/ClaudeGuardian" "$APP/Contents/MacOS/ClaudeGuardian"
cp "icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Claude Guardian</string>
    <key>CFBundleDisplayName</key>        <string>Claude Guardian</string>
    <key>CFBundleIdentifier</key>         <string>local.claude-guardian</string>
    <key>CFBundleExecutable</key>         <string>ClaudeGuardian</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>            <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Claude Guardian uses this to bring the terminal tab running your Claude Code session to the front.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# Il Finder memorizza le icone: aggiornando la data del bundle mostra subito quella nuova.
touch "$APP"

echo "✓ App pronta: $(pwd)/$APP (versione $VERSION, build $BUILD)"
echo "  Per installarla: cp -R \"$APP\" /Applications/ && open \"/Applications/Claude Guardian.app\""
