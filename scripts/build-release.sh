#!/bin/bash
# Build a verified, ad-hoc-signed local KokoroVoice app.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
LOG_DIR="$PROJECT_DIR/build"
CODEX_BUILD_CACHE_ROOT="${HOME}/Library/Caches/codex-builds"
XCODE_RESOLUTION_SOURCE="$PROJECT_DIR/XcodePackage.resolved"

for command_name in xcodegen xcodebuild codesign ditto; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "[error] Required command is missing: $command_name" >&2
        exit 1
    fi
done

"$SCRIPT_DIR/download-models.sh"

mkdir -p "$CODEX_BUILD_CACHE_ROOT"
if [ -n "${KOKORO_DERIVED_DATA_DIR:-}" ]; then
    DERIVED_DATA_DIR="$KOKORO_DERIVED_DATA_DIR"
    mkdir -p "$DERIVED_DATA_DIR"
else
    DERIVED_DATA_DIR="$(mktemp -d "$CODEX_BUILD_CACHE_ROOT/kokoro-voice.XXXXXXXX")"
fi

echo "DerivedData: $DERIVED_DATA_DIR"

rm -rf "$DIST_DIR" "$LOG_DIR"
mkdir -p "$DIST_DIR" "$LOG_DIR"

cd "$PROJECT_DIR"
xcodegen generate --spec project-unsigned.yml

if [ ! -f "$XCODE_RESOLUTION_SOURCE" ]; then
    echo "[error] Missing Xcode dependency lock: $XCODE_RESOLUTION_SOURCE" >&2
    exit 1
fi
XCODE_RESOLUTION_DIR="$PROJECT_DIR/KokoroVoice.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$XCODE_RESOLUTION_DIR"
cp "$XCODE_RESOLUTION_SOURCE" "$XCODE_RESOLUTION_DIR/Package.resolved"

BUILD_LOG="$LOG_DIR/xcodebuild.log"
set -o pipefail
xcodebuild \
    -project KokoroVoice.xcodeproj \
    -scheme KokoroVoice \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGN_IDENTITY='-' \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    build 2>&1 | tee "$BUILD_LOG"

APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release/KokoroVoice.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/KokoroVoice"
APP_PLIST="$APP_PATH/Contents/Info.plist"
APP_EXTENSION="$APP_PATH/Contents/PlugIns/KokoroVoiceExtension.appex"
APP_FRAMEWORK="$APP_PATH/Contents/Frameworks/KokoroVoiceShared.framework"
EXTENSION_ENTITLEMENTS="$PROJECT_DIR/KokoroVoiceExtension/KokoroVoiceExtension-unsigned.entitlements"
APP_MODEL="$APP_PATH/Contents/Resources/Resources/kokoro-v1_0.safetensors"
APP_VOICES="$APP_PATH/Contents/Resources/Resources/voices"

for required_path in "$APP_EXECUTABLE" "$APP_PLIST" "$APP_EXTENSION" "$APP_FRAMEWORK" "$EXTENSION_ENTITLEMENTS" "$APP_MODEL" "$APP_VOICES"; do
    if [ ! -e "$required_path" ]; then
        echo "[error] Built app is incomplete: $required_path is missing" >&2
        exit 1
    fi
done

voice_count="$(find "$APP_VOICES" -maxdepth 1 -type f -name '*.safetensors' | wc -l | tr -d ' ')"
model_copy_count="$(find "$APP_PATH" -type f -name 'kokoro-v1_0.safetensors' | wc -l | tr -d ' ')"
if [ "$voice_count" != "36" ]; then
    echo "[error] Built app contains $voice_count voices; expected 36" >&2
    exit 1
fi
if [ "$model_copy_count" != "1" ]; then
    echo "[error] Built app contains $model_copy_count model copies; expected exactly one" >&2
    exit 1
fi

codesign --force --sign - --timestamp=none "$APP_FRAMEWORK"
codesign --force --sign - --timestamp=none --entitlements "$EXTENSION_ENTITLEMENTS" "$APP_EXTENSION"
codesign --force --sign - --timestamp=none "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if ! codesign -d --entitlements - "$APP_EXTENSION" 2>/dev/null |
     grep -A2 -F '[Key] com.apple.security.app-sandbox' |
     grep -Fq '[Bool] true'; then
    echo "[error] Built extension is missing its required App Sandbox entitlement" >&2
    exit 1
fi

ditto "$APP_PATH" "$DIST_DIR/KokoroVoice.app"
cp "$SCRIPT_DIR/install.sh" "$DIST_DIR/install.sh"
chmod +x "$DIST_DIR/install.sh"
printf '%s\n' "3778042d417811dbbc94cd7aa8784858bbc47429 + local hardening" > "$DIST_DIR/BUILD_SOURCE"

echo "Built and verified: $DIST_DIR/KokoroVoice.app"
echo "DerivedData retained for this run: $DERIVED_DATA_DIR"
