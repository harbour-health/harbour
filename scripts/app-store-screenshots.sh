#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
usage() { echo "Usage: scripts/app-store-screenshots.sh [--locale en-CA|fr-CA] [--output DIRECTORY]"; }
locale=en-CA
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --locale) locale="${2:?Missing locale}"; shift 2 ;;
        --output) output="${2:?Missing output directory}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
case "$locale" in
    en-CA) test_name=testCaptureEnglish ;;
    fr-CA) test_name=testCaptureFrench ;;
    *) echo "Supported locales: en-CA and fr-CA" >&2; exit 2 ;;
esac
runtime=com.apple.CoreSimulator.SimRuntime.iOS-26-5
device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max
python="${PYTHON:-python3}"
command -v "$python" >/dev/null
"$python" -c 'from PIL import Image, ImageDraw' || { echo "Install Pillow in your Python environment before running this workflow." >&2; exit 1; }
[[ -f "$root/HarbourRuntime/Vendor/llama.xcframework/Info.plist" ]] || { echo "Missing prepared llama.xcframework; follow docs/local-models.md first. This script does not download it." >&2; exit 1; }
# The prepared path makes this an idempotent privacy-manifest refresh, without downloads.
HARBOUR_RUNTIME_VENDOR="$root/HarbourRuntime/Vendor" bash "$root/scripts/prepare-runtime.sh"
xcrun simctl list runtimes -j | "$python" -c 'import json,sys; name=sys.argv[1]; assert any(r["identifier"]==name and r["isAvailable"] for r in json.load(sys.stdin)["runtimes"]), "Install iOS 26.5 in Xcode first; this script does not download runtimes."' "$runtime"
xcrun simctl list devicetypes -j | "$python" -c 'import json,sys; name=sys.argv[1]; assert any(r["identifier"]==name for r in json.load(sys.stdin)["devicetypes"]), "iPhone 17 Pro Max device type unavailable."' "$device_type"
output="${output:-$root/build/app-store-screenshots/$locale/$(date -u +%Y%m%dT%H%M%SZ)}"
[[ ! -e "$output" ]] || { echo "Output already exists; choose a new directory to preserve prior results: $output" >&2; exit 1; }
mkdir -p "$output/run"
output="$(cd "$output" && pwd)"
derived_data="${HARBOUR_SCREENSHOT_DERIVED_DATA:-$root/build/app-store-screenshots/DerivedData}"
device=""
cleanup() {
    if [[ -n "$device" ]]; then
        xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
        xcrun simctl delete "$device" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
device="$(xcrun simctl create "HarbourAppStore-$(date -u +%Y%m%dT%H%M%SZ)" "$device_type" "$runtime")"
printf '%s\n' "$device" > "$output/run/simulator-uuid.txt"
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcrun simctl ui "$device" appearance light
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcodebuild -version > "$output/run/xcode-version.txt"
# One worker and one build job: never clone a personal QA simulator.
xcodebuild -quiet test -project "$root/Harbour.xcodeproj" -scheme Harbour -configuration Debug \
    -destination "platform=iOS Simulator,id=$device" -destination-timeout 60 \
    -derivedDataPath "$derived_data" -resultBundlePath "$output/run/screenshots.xcresult" \
    -only-testing:"HarbourUITests/HarbourAppStoreScreenshotTests/$test_name" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -jobs 1 \
    2>&1 | tee "$output/run/xcodebuild.log"
"$python" "$root/scripts/export-app-store-screenshots.py" "$output/run/screenshots.xcresult" "$output" "$locale"
printf 'Generated ten native iPhone PNGs: %s\nReview contact-sheet.jpg and manifest.json before uploading.\n' "$output"
