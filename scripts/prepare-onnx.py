#!/usr/bin/env python3
"""Package Microsoft's verified static ONNX Runtime and its unmodified ObjC bindings."""
from pathlib import Path
import hashlib
import shutil
import subprocess
import urllib.request
import zipfile

root = Path(__file__).resolve().parent.parent
work = Path('/private/tmp/harbour-onnx-build')
vendor = root / 'HarbourSpeech/Vendor'
work.mkdir(parents=True, exist_ok=True)
vendor.mkdir(parents=True, exist_ok=True)
archive = work / 'onnxruntime-1.24.2.zip'
expected = 'f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54'
if not archive.exists():
    urllib.request.urlretrieve('https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip', archive)
with archive.open('rb') as handle:
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b''):
        digest.update(chunk)
    assert digest.hexdigest() == expected
sdk = work / 'sdk'
if not sdk.exists():
    with zipfile.ZipFile(archive) as bundle:
        assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in bundle.namelist())
        bundle.extractall(sdk)
framework = next(sdk.rglob('onnxruntime.xcframework'))
headers = work / 'headers'
if headers.exists(): shutil.rmtree(headers)
headers.mkdir(exist_ok=True)
shutil.copytree(framework / 'ios-arm64/onnxruntime.framework/Headers', headers / 'onnxruntime')
# Only the Objective-C bindings consume these C headers; no Swift module is
# needed. A root modulemap would collide with other static XCFrameworks.
(headers / 'module.modulemap').unlink(missing_ok=True)
libraries = []
for name in ['ios-arm64', 'ios-arm64_x86_64-simulator', 'macos-arm64_x86_64']:
    source = framework / name / 'onnxruntime.framework/onnxruntime'
    # zipfile extracts macOS framework symlinks as text; use the actual archive.
    if name.startswith('macos'):
        source = source.parent / 'Versions/A/onnxruntime'
    target = work / name / 'libOrtStatic.a'
    target.parent.mkdir(exist_ok=True)
    shutil.copyfile(source, target)
    libraries += ['-library', str(target), '-headers', str(headers)]
artifact = vendor / 'OrtStatic.xcframework'
if artifact.exists(): shutil.rmtree(artifact)
subprocess.run(['xcodebuild', '-create-xcframework', *libraries, '-output', str(artifact)], check=True)
# The old SwiftPM repository is unavailable. Use the official published source
# pod matching the already-pinned C binary, not a moving branch or third-party mirror.
# https://trunk.cocoapods.org/api/v1/pods/onnxruntime-objc/specs/1.24.2
objc_archive = work / 'onnxruntime-objc-1.24.2.zip'
objc_expected = 'ab102b30f15c44b08dc6fc32683abeafd216ff6bcabdf74fbac37fbb19d80eed'
if not objc_archive.exists():
    urllib.request.urlretrieve('https://download.onnxruntime.ai/pod-archive-onnxruntime-objc-1.24.2.zip', objc_archive)
if hashlib.sha256(objc_archive.read_bytes()).hexdigest() != objc_expected:
    raise SystemExit('ONNX Runtime Objective-C source checksum mismatch.')
source = work / 'objc-source-1.24.2'
if source.exists(): shutil.rmtree(source)
with zipfile.ZipFile(objc_archive) as bundle:
    if any(Path(n).is_absolute() or '..' in Path(n).parts for n in bundle.namelist()):
        raise SystemExit('Unsafe path in ONNX Runtime Objective-C source archive.')
    bundle.extractall(source)
bindings = vendor / 'OnnxRuntimeBindings'
if bindings.exists(): shutil.rmtree(bindings)
shutil.copytree(source / 'objectivec', bindings)
shutil.copyfile(source / 'LICENSE', vendor / 'ONNX-LICENSE')
print('Prepared verified static ONNX Runtime 1.24.2 and official bindings.')
