#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="LidStay"
APP_OUT_DIR="${APP_OUT_DIR:-/Applications}"
APP_BUNDLE="${APP_OUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
UNIVERSAL="${UNIVERSAL:-0}"
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

cd "$ROOT_DIR"

if [ "$UNIVERSAL" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${APP_NAME}"
else
    swift build -c release
    BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${ROOT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
chmod +x "${MACOS_DIR}/${APP_NAME}"

if [ -n "$APP_VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"
fi
if [ -n "$BUILD_NUMBER" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"
fi

codesign --force --deep --sign - "$APP_BUNDLE"

if [ "$UNIVERSAL" = "1" ]; then
    lipo -info "${MACOS_DIR}/${APP_NAME}"
fi

echo "Built and installed: ${APP_BUNDLE}"
