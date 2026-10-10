#!/bin/bash
# Compila l'app e la impacchetta in "build/Claude Guardian.app" (firmata ad-hoc).
# Requisiti: macOS 13+, Xcode o Command Line Tools (xcode-select --install).
#
# Uso:
#   ./build-app.sh            build per l'architettura di questo Mac
#   ./build-app.sh --release  build universale (arm64 + x86_64) e zip da allegare
#                             alla release GitHub: build/ClaudeGuardian-<versione>.zip
set -euo pipefail

RELEASE=0
case "${1:-}" in
  "") ;;
  --release) RELEASE=1 ;;
  *) echo "Uso: $0 [--release]" >&2; exit 1 ;;
esac

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

if [ "$RELEASE" = 1 ]; then
  # Binario universale, per Mac Apple Silicon e Intel.
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ClaudeGuardian"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/ClaudeGuardian"
fi

APP="build/Claude Guardian.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeGuardian"
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

echo "✓ App pronta: $(pwd)/$APP (versione $VERSION, build $BUILD, $(lipo -archs "$APP/Contents/MacOS/ClaudeGuardian"))"

if [ "$RELEASE" = 0 ]; then
  echo "  Per installarla: cp -R \"$APP\" /Applications/ && open \"/Applications/Claude Guardian.app\""
  exit 0
fi

# Lo zip contiene l'app e gli hook, perché senza hook l'app non vede nessuna sessione.
# ditto (non zip) preserva la struttura e la firma del bundle; --norsrc evita le cartelle __MACOSX.
NAME="ClaudeGuardian-$VERSION"
STAGE="build/$NAME"
ZIP="build/$NAME.zip"
rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Claude Guardian.app"
ditto ../hooks "$STAGE/hooks"
cp ../install-hooks.sh ../LICENSE "$STAGE/"
ditto -c -k --norsrc --keepParent "$STAGE" "$ZIP"
rm -rf "$STAGE"

echo "✓ Release pronta: $(pwd)/$ZIP"
echo "  SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
