#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
vendor="${HARBOUR_RUNTIME_VENDOR:-$root/HarbourRuntime/Vendor}"
if [[ -f "$vendor/llama.xcframework/Info.plist" ]]; then
    echo "Native runtime already prepared."
    exit 0
fi
command -v cmake >/dev/null || { echo "CMake is required (brew install cmake)."; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/harbour-runtime.XXXXXX")"
trap 'rm -rf "$work"' EXIT
curl --fail --location --retry 2 https://github.com/ggml-org/llama.cpp/releases/download/b10549/llama-b10549-xcframework.zip -o "$work/runtime.zip"
echo "636709d4a7b49ac7f2ed6dc8a4de3f278c257cac7248fe40d6a513f671e4bff4  $work/runtime.zip" | shasum -a 256 -c -
unzip -q "$work/runtime.zip" -d "$work/release"
curl --fail --location --retry 2 https://codeload.github.com/ggml-org/llama.cpp/tar.gz/refs/tags/b10549 -o "$work/source.tar.gz"
echo "418ef98f058952c4f2e1fba0f77a73cbbfac2e5bf4146a0dc3202777ed5d9c1f  $work/source.tar.gz" | shasum -a 256 -c -
mkdir "$work/source"
tar -xzf "$work/source.tar.gz" -C "$work/source" --strip-components=1
cmake -S "$work/source" -B "$work/build" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
    '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
    -DBUILD_SHARED_LIBS=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF \
    -DLLAMA_BUILD_MTMD=OFF -DGGML_METAL=OFF -DGGML_BLAS=ON -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF
cmake --build "$work/build" --config Release -j 4
release="$(find "$work/release" -name llama.xcframework -type d | head -1)"
[[ -d "$release/ios-arm64/llama.framework" ]] || { echo "Release framework layout not recognised."; exit 1; }
ditto "$release/ios-arm64/llama.framework" "$work/sim/llama.framework"
rm "$work/sim/llama.framework/llama"
xcrun libtool -static -o "$work/combined.a" \
    "$work/build/src/Release-iphonesimulator/libllama.a" \
    "$work/build/ggml/src/Release-iphonesimulator/libggml.a" \
    "$work/build/ggml/src/Release-iphonesimulator/libggml-base.a" \
    "$work/build/ggml/src/Release-iphonesimulator/libggml-cpu.a" \
    "$work/build/ggml/src/ggml-blas/Release-iphonesimulator/libggml-blas.a"
xcrun --sdk iphonesimulator clang++ -dynamiclib -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -arch arm64 -arch x86_64 -mios-simulator-version-min=18.0 \
    -Wl,-force_load,"$work/combined.a" -framework Foundation -framework Metal -framework Accelerate \
    -install_name @rpath/llama.framework/llama -o "$work/sim/llama.framework/llama"
/usr/libexec/PlistBuddy -c 'Set :CFBundleSupportedPlatforms:0 iPhoneSimulator' "$work/sim/llama.framework/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :DTPlatformName iphonesimulator' "$work/sim/llama.framework/Info.plist"
mkdir -p "$vendor"
xcodebuild -create-xcframework \
    -framework "$release/ios-arm64/llama.framework" \
    -framework "$release/macos-arm64_x86_64/llama.framework" \
    -framework "$work/sim/llama.framework" -output "$vendor/llama.xcframework"
echo "Native runtime prepared. Open Harbour.xcodeproj."
