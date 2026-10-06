#!/bin/bash
set -e

SWIFT_EXTRA_FLAGS=()
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  if DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license status >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  else
    SWIFTUI_MACRO="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
    if [ -f "$SWIFTUI_MACRO" ]; then
      SWIFT_EXTRA_FLAGS+=(-Xswiftc -load-plugin-library -Xswiftc "$SWIFTUI_MACRO")
    fi
  fi
fi

CONFIGURATION="release"
ACTION="build"

while [[ $# -gt 0 ]]; do
  case $1 in
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    run)
      ACTION="run"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

SCRATCH_DIR="/tmp/foldydock-build"
echo "🚀 Compiling FoldyDock ($CONFIGURATION)..."
swift build -c "$CONFIGURATION" --scratch-path "$SCRATCH_DIR" "${SWIFT_EXTRA_FLAGS[@]}"

BIN_PATH="$SCRATCH_DIR/arm64-apple-macosx/$CONFIGURATION/FoldyDock"
if [ ! -f "$BIN_PATH" ]; then
  BIN_PATH="$SCRATCH_DIR/$CONFIGURATION/FoldyDock"
fi
if [ ! -f "$BIN_PATH" ]; then
  BIN_PATH=$(find "$SCRATCH_DIR" -type f -name "FoldyDock" -perm +111 2>/dev/null | grep -v "\.build" | head -n 1)
fi

if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
    echo "❌ Binary not found at $BIN_PATH"
    exit 1
fi

APP_NAME="FoldyDock.app"
DIST_DIR="build"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "📦 Packaging $APP_NAME..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

cp "$BIN_PATH" "$MACOS/FoldyDock"
chmod +x "$MACOS/FoldyDock"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ -f "$PROJECT_DIR/logoFoldyDock.png" ]; then
    cp "$PROJECT_DIR/logoFoldyDock.png" "$RESOURCES/logoFoldyDock.png"
elif [ -f "logoFoldyDock.png" ]; then
    cp "logoFoldyDock.png" "$RESOURCES/logoFoldyDock.png"
fi

if [ -f "$PROJECT_DIR/menuBarIcon.png" ]; then
    cp "$PROJECT_DIR/menuBarIcon.png" "$RESOURCES/menuBarIcon.png"
elif [ -f "menuBarIcon.png" ]; then
    cp "menuBarIcon.png" "$RESOURCES/menuBarIcon.png"
fi

if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$RESOURCES/AppIcon.icns"
elif [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

cat <<EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleExecutable</key>
    <string>FoldyDock</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.foldydock.FoldyDock</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FoldyDock</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ $APP_NAME assembled successfully in $DIST_DIR!"

if [ "$ACTION" = "run" ]; then
    echo "🌟 Launching $APP_NAME..."
    killall -9 FoldyDock 2>/dev/null || true
    open "$APP_BUNDLE"
fi
