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
source = work / 'source'
if not source.exists():
    subprocess.run(['git', 'clone', '--depth', '1', '--branch', '1.24.2', 'https://github.com/microsoft/onnxruntime-swift-package-manager.git', str(source)], check=True)
assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == 'b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2'
bindings = vendor / 'OnnxRuntimeBindings'
if bindings.exists(): shutil.rmtree(bindings)
shutil.copytree(source / 'objectivec', bindings)
shutil.copyfile(source / 'LICENSE', vendor / 'ONNX-LICENSE')
print('Prepared verified static ONNX Runtime 1.24.2 and official bindings.')
