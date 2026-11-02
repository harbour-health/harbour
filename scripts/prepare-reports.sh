#!/bin/bash
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET=13.0
export IPHONEOS_DEPLOYMENT_TARGET=18.0
root="$(cd "$(dirname "$0")/.." && pwd)"
crate="$root/HarbourReports/Renderer"
vendor="$root/HarbourReports/Vendor"
if [[ -f "$vendor/HarbourTypst.xcframework/Info.plist" && "${1:-}" != "--force" ]]; then
    echo "Report renderer already prepared."
    exit 0
fi
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
for target in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    cargo build --manifest-path "$crate/Cargo.toml" --release --locked --target "$target"
done
mkdir -p "$vendor/simulator"
work="$(mktemp -d "$vendor/report-build.XXXXXX")"
trap 'rm -rf "$work"' EXIT
xcrun lipo -create "$crate/target/aarch64-apple-ios-sim/release/libharbour_typst.a" "$crate/target/x86_64-apple-ios/release/libharbour_typst.a" -output "$vendor/simulator/libharbour_typst.a"
xcodebuild -create-xcframework \
    -library "$crate/target/aarch64-apple-ios/release/libharbour_typst.a" -headers "$crate/include" \
    -library "$vendor/simulator/libharbour_typst.a" -headers "$crate/include" \
    -library "$crate/target/aarch64-apple-darwin/release/libharbour_typst.a" -headers "$crate/include" \
    -output "$work/HarbourTypst.xcframework"
rm -rf "$vendor/HarbourTypst.xcframework"
mv "$work/HarbourTypst.xcframework" "$vendor/HarbourTypst.xcframework"
echo "Embedded Typst report renderer prepared."
