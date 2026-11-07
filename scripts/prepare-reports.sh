#!/bin/bash
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET=13.0
export IPHONEOS_DEPLOYMENT_TARGET=18.0
root="$(cd "$(dirname "$0")/.." && pwd)"
crate="$root/HarbourReports/Renderer"
vendor="$root/HarbourReports/Vendor"
fingerprint="$(python3 - "$crate" <<'PY'
import hashlib
from pathlib import Path
import sys
root = Path(sys.argv[1])
digest = hashlib.sha256()
for path in sorted([root / 'Cargo.toml', root / 'Cargo.lock', *root.glob('src/**/*'), *root.glob('fonts/**/*')]):
    if path.is_file():
        digest.update(str(path.relative_to(root)).encode())
        digest.update(path.read_bytes())
print(digest.hexdigest())
PY
)"
if [[ -f "$vendor/HarbourTypst.xcframework/Info.plist" && -f "$vendor/renderer-source.sha256" && "$(cat "$vendor/renderer-source.sha256")" == "$fingerprint" && "${1:-}" != "--force" ]]; then
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
printf '%s\n' "$fingerprint" > "$vendor/renderer-source.sha256"
echo "Embedded Typst report renderer prepared."
