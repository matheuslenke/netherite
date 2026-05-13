#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Netherite"
BUNDLE_ID="dev.matheuslenke.Netherite"
MIN_SYSTEM_VERSION="26.0"
CONFIGURATION="${CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
LOGO_SOURCE="$ROOT_DIR/Sources/Netherite/Resources/NetheriteLogo.png"
ICON_NAME="Netherite"

stage_icon() {
  [[ -f "$LOGO_SOURCE" ]] || return 0

  cp "$LOGO_SOURCE" "$APP_RESOURCES/NetheriteLogo.png"

  if ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
    return 0
  fi

  local iconset="$DIST_DIR/$ICON_NAME.iconset"
  rm -rf "$iconset"
  mkdir -p "$iconset"

  sips -z 16 16 "$LOGO_SOURCE" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32 "$LOGO_SOURCE" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$LOGO_SOURCE" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64 "$LOGO_SOURCE" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$LOGO_SOURCE" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256 "$LOGO_SOURCE" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$LOGO_SOURCE" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512 "$LOGO_SOURCE" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$LOGO_SOURCE" --out "$iconset/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$LOGO_SOURCE" --out "$iconset/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$iconset" -o "$APP_RESOURCES/$ICON_NAME.icns"
  rm -rf "$iconset"
}

stage_app() {
  swift build -c "$CONFIGURATION"
  BUILD_BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  mkdir -p "$APP_RESOURCES"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  stage_icon

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

source_signature() {
  {
    printf '%s\n' "Package.swift"
    find Sources -type f -print
  } | sort | while IFS= read -r path; do
    [[ -e "$path" ]] || continue
    stat -f '%m %z %N' "$path"
  done
}

hot_reload() {
  local last_signature=""
  local next_signature
  local poll_interval="${HOT_RELOAD_INTERVAL:-1}"

  echo "Hot reload watching Package.swift and Sources/. Press Ctrl-C to stop."

  while true; do
    next_signature="$(source_signature)"
    if [[ "$next_signature" != "$last_signature" ]]; then
      last_signature="$next_signature"
      echo "Changes detected; rebuilding and relaunching $APP_NAME..."
      pkill -x "$APP_NAME" >/dev/null 2>&1 || true
      if stage_app; then
        open_app
      else
        echo "Build failed; waiting for the next change." >&2
      fi
    fi
    sleep "$poll_interval"
  done
}

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

case "$MODE" in
  run)
    stage_app
    open_app
    ;;
  --bundle|bundle)
    stage_app
    ;;
  --debug|debug)
    stage_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stage_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stage_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stage_app
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --hot-reload|hot-reload|--watch|watch)
    hot_reload
    ;;
  *)
    echo "usage: $0 [run|--bundle|--debug|--logs|--telemetry|--verify|--hot-reload]" >&2
    exit 2
    ;;
esac
