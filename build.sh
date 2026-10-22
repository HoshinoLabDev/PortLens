#!/bin/bash
# 构建 PortLens.app：编译 + 图标 + CLI(Helpers) + 组装
set -e
cd "$(dirname "$0")"

DEV_DIR="$(pwd)"
APP_NAME="PortLens"
APP_VERSION="1.0"
APP_BUNDLE="$DEV_DIR/build/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
HELPERS="$CONTENTS/Helpers"
SWIFTC="${SWIFTC:-$(xcrun -f swiftc)}"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"

CORE_SOURCES="Sources/Models.swift Sources/USBMonitor.swift Sources/Diagnostics.swift Sources/ProModels.swift Sources/ProDataSources.swift Sources/CableVendorDB.swift Sources/ProLogic.swift Sources/DisplayDiagnostics.swift Sources/USBIFXIDDB.swift Sources/ThunderboltFabric.swift Sources/DeviceIdentity.swift"

echo "==> 编译主程序"
"$SWIFTC" -O -swift-version 5 -parse-as-library \
  $CORE_SOURCES \
  Sources/Views.swift Sources/ProIntegration.swift Sources/ProViews.swift Sources/SettingsView.swift \
  -o "$DEV_DIR/PortLens.bin" \
  -framework AppKit -framework SwiftUI -framework Combine -framework IOKit -framework Charts -framework UserNotifications

echo "==> 编译 CLI（Contents/Helpers/portlens）"
mkdir -p "$HELPERS"
"$SWIFTC" -O -swift-version 5 -parse-as-library \
  $CORE_SOURCES \
  Sources/CLI.swift \
  -o "$DEV_DIR/portlens-cli.bin" \
  -framework Foundation -framework AppKit -framework IOKit -framework CoreGraphics
cp "$DEV_DIR/portlens-cli.bin" "$HELPERS/portlens"
chmod +x "$HELPERS/portlens"

echo "==> 编译 Widget Extension（Contents/PlugIns/PortLensWidget.appex）"
WIDGET_SRC="$DEV_DIR/WidgetExtension"
WIDGET_BUILD="$DEV_DIR/build/PortLensWidget.appex"
rm -rf "$WIDGET_BUILD"
mkdir -p "$WIDGET_BUILD/Contents/MacOS"
"$SWIFTC" -O -swift-version 5 -parse-as-library \
  "$WIDGET_SRC/PortLensWidget.swift" \
  -o "$WIDGET_BUILD/Contents/MacOS/PortLensWidget" \
  -framework WidgetKit -framework SwiftUI -framework AppKit
cp "$WIDGET_SRC/Info.plist" "$WIDGET_BUILD/Contents/Info.plist"
codesign --force --sign - --entitlements "$WIDGET_SRC/entitlements.plist" "$WIDGET_BUILD" 2>/dev/null || true

echo "==> 生成图标"
"$SWIFTC" -O -swift-version 5 gen_icon.swift -o "$DEV_DIR/gen_icon.bin" -framework AppKit
rm -rf "$DEV_DIR/AppIcon.iconset"
"$DEV_DIR/gen_icon.bin" "$DEV_DIR/AppIcon.iconset"
iconutil -c icns "$DEV_DIR/AppIcon.iconset" -o "$DEV_DIR/AppIcon.icns"

echo "==> 组装 .app"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES" "$HELPERS" "$CONTENTS/PlugIns"
cp "$DEV_DIR/PortLens.bin" "$MACOS/$APP_NAME"
cp "$DEV_DIR/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$DEV_DIR/portlens-cli.bin" "$HELPERS/portlens"
cp -R "$WIDGET_BUILD" "$CONTENTS/PlugIns/PortLensWidget.appex"
chmod +x "$HELPERS/portlens"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>PortLens</string>
    <key>CFBundleDisplayName</key>
    <string>PortLens</string>
    <key>CFBundleIdentifier</key>
    <string>com.marvis.portlens</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleExecutable</key>
    <string>PortLens</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

codesign --force --sign - --entitlements "$WIDGET_SRC/entitlements.plist" "$APP_BUNDLE" 2>/dev/null || true

OUT_DIR="${OUT_DIR:-$HOME/Desktop}"
echo "==> 复制到 $OUT_DIR"
mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$OUT_DIR/$APP_NAME.app"
echo "构建完成: $OUT_DIR/$APP_NAME.app"
echo "CLI: $OUT_DIR/$APP_NAME.app/Contents/Helpers/portlens"
