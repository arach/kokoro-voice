#!/bin/bash
# Install the already-built, verified local app without bypassing Gatekeeper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="KokoroVoice.app"
APP_PATH="$SCRIPT_DIR/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"
STAGING_PATH="/Applications/.KokoroVoice.installing.$$"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
REPLACE_EXISTING=0
BACKUP_PATH=""
BACKUP_ROOT="${HOME}/Library/Application Support/KokoroVoice/Backups"
INSTALL_PLACED=0

if [ "${1:-}" = "--replace" ]; then
    REPLACE_EXISTING=1
elif [ "$#" -gt 0 ]; then
    echo "Usage: $0 [--replace]" >&2
    exit 2
fi

cleanup() {
    status=$?
    trap - EXIT

    if [ -e "$STAGING_PATH" ]; then
        rm -rf "$STAGING_PATH"
    fi

    if [ "$status" -ne 0 ]; then
        if [ "$INSTALL_PLACED" = "1" ]; then
            installed_extension="$INSTALL_PATH/Contents/PlugIns/KokoroVoiceExtension.appex"
            pluginkit -r "$installed_extension" >/dev/null 2>&1 || true
            rm -rf "$INSTALL_PATH"
        fi

        if [ -n "$BACKUP_PATH" ] && [ -e "$BACKUP_PATH" ]; then
            mv "$BACKUP_PATH" "$INSTALL_PATH"
            pluginkit -a "$INSTALL_PATH/Contents/PlugIns/KokoroVoiceExtension.appex" >/dev/null 2>&1 || true
            echo "Previous installation restored after failure: $INSTALL_PATH" >&2
        elif [ "$INSTALL_PLACED" = "1" ]; then
            echo "Incomplete installation rolled back: $INSTALL_PATH" >&2
        fi
    fi

    exit "$status"
}
trap cleanup EXIT

if [ "$(uname -m)" != "arm64" ]; then
    echo "[error] Apple silicon is required" >&2
    exit 1
fi

if [ ! -x "$LSREGISTER" ]; then
    echo "[error] LaunchServices registration tool is unavailable: $LSREGISTER" >&2
    exit 1
fi

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$macos_major" -lt 15 ]; then
    echo "[error] macOS 15 or newer is required" >&2
    exit 1
fi

APP_EXECUTABLE="$APP_PATH/Contents/MacOS/KokoroVoice"
APP_PLIST="$APP_PATH/Contents/Info.plist"
APP_EXTENSION="$APP_PATH/Contents/PlugIns/KokoroVoiceExtension.appex"
EXTENSION_PLIST="$APP_EXTENSION/Contents/Info.plist"
APP_MODEL="$APP_EXTENSION/Contents/Resources/Resources/kokoro-v1_0.safetensors"
APP_VOICES="$APP_EXTENSION/Contents/Resources/Resources/voices"

for required_path in "$APP_EXECUTABLE" "$APP_PLIST" "$APP_EXTENSION" "$EXTENSION_PLIST" "$APP_MODEL" "$APP_VOICES"; do
    if [ ! -e "$required_path" ]; then
        echo "[error] Refusing to install incomplete app: $required_path is missing" >&2
        exit 1
    fi
done

app_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PLIST")"
extension_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXTENSION_PLIST")"
component_type="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:AudioComponents:0:type' "$EXTENSION_PLIST")"
component_subtype="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:AudioComponents:0:subtype' "$EXTENSION_PLIST")"
component_manufacturer="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:AudioComponents:0:manufacturer' "$EXTENSION_PLIST")"

if [ "$app_bundle_id" != "app.openscout.kokorovoice" ] ||
   [ "$extension_bundle_id" != "app.openscout.kokorovoice.extension" ] ||
   [ "$component_type" != "ausp" ] ||
   [ "$component_subtype" != "KOKV" ] ||
   [ "$component_manufacturer" != "OSCT" ]; then
    echo "[error] Refusing to install an artifact with unexpected bundle or Audio Unit identity" >&2
    exit 1
fi

voice_count="$(find "$APP_VOICES" -maxdepth 1 -type f -name '*.safetensors' | wc -l | tr -d ' ')"
if [ "$voice_count" != "36" ]; then
    echo "[error] Refusing to install app with $voice_count voices; expected 36" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
if ! codesign -d --entitlements - "$APP_EXTENSION" 2>/dev/null |
     grep -A2 -F '[Key] com.apple.security.app-sandbox' |
     grep -Fq '[Bool] true'; then
    echo "[error] Refusing to install an extension without App Sandbox enabled" >&2
    exit 1
fi

if [ -e "$INSTALL_PATH" ]; then
    if [ "$REPLACE_EXISTING" != "1" ]; then
        echo "[error] $INSTALL_PATH already exists; rerun with --replace after reviewing it" >&2
        exit 1
    fi
    mkdir -p "$BACKUP_ROOT"
    BACKUP_PATH="$BACKUP_ROOT/KokoroVoice.$(date '+%Y%m%d-%H%M%S').app"
    pluginkit -r "$INSTALL_PATH/Contents/PlugIns/KokoroVoiceExtension.appex" >/dev/null 2>&1 || true
    mv "$INSTALL_PATH" "$BACKUP_PATH"
    echo "Existing install preserved at: $BACKUP_PATH"
fi

ditto "$APP_PATH" "$STAGING_PATH"
codesign --verify --deep --strict --verbose=2 "$STAGING_PATH"
mv "$STAGING_PATH" "$INSTALL_PATH"
INSTALL_PLACED=1

installed_extension="$INSTALL_PATH/Contents/PlugIns/KokoroVoiceExtension.appex"
"$LSREGISTER" -f -R -trusted "$INSTALL_PATH"
pluginkit -a "$installed_extension"

registration_visible=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if pluginkit -m -A -D -vv -i 'app.openscout.kokorovoice.extension' |
       grep -Fq "Path = $installed_extension"; then
        registration_visible=1
        break
    fi
    sleep 1
done

if [ "$registration_visible" != "1" ]; then
    echo "[error] macOS did not report the registered Kokoro extension" >&2
    exit 1
fi

killall speechsynthesisd 2>/dev/null || true

echo "Installed and registered: $INSTALL_PATH"
echo "Launch the app once, then select a Kokoro voice in OpenScout Settings > Voice."
