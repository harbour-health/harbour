#!/usr/bin/env python3
"""Build pinned eSpeak NG phonemization for Kokoro: Mac, iPhone and simulator."""
from pathlib import Path
import argparse
import shutil
import plistlib
import subprocess

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=Path, default=Path('/private/tmp/harbour-speech-build'))
args = parser.parse_args()
source = args.work / 'espeak-ng'
revision = '4870adfa25b1a32b4361592f1be8a40337c58d6c'
vendor = root / 'HarbourSpeech/Vendor'
artifact = vendor / 'EspeakNG.xcframework'
resources = root / 'HarbourSpeech/Sources/HarbourSpeech/Resources'

def run(*command):
    subprocess.run([str(c) for c in command], check=True)

args.work.mkdir(parents=True, exist_ok=True)
if not source.exists():
    run('git', 'clone', '--depth', '1', '--branch', '1.52.0', 'https://github.com/espeak-ng/espeak-ng.git', source)
assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == revision
# Upstream otherwise fetches Sonic even when USE_LIBSONIC=OFF. It is not used.
deps = source / 'cmake/deps.cmake'
text = deps.read_text()
if 'elseif(USE_LIBSONIC)' not in text:
    assert text.count('else()') == 1
    deps.write_text(text.replace('else()', 'elseif(USE_LIBSONIC)'))
# Recent iOS SDKs expose sys/endian.h without the conversion macros. Use the
# upstream Apple OSByteOrder branch on every Apple target.
endian = source / 'src/include/compat/endian.h'
text = endian.read_text()
text = text.replace('#if __has_include_next(<endian.h>)\n', '#if __has_include_next(<endian.h>) && !defined(__APPLE__)\n')
text = text.replace('#elif __has_include(<sys/endian.h>)\n', '#elif __has_include(<sys/endian.h>) && !defined(__APPLE__)\n')
endian.write_text(text)
common = ['-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_MACOSX_BUNDLE=OFF', '-DCMAKE_C_FLAGS=-DN_PATH_HOME=1024', '-DBUILD_TESTING=OFF', '-DUSE_ASYNC=OFF', '-DUSE_SPEECHPLAYER=OFF', '-DUSE_MBROLA=OFF', '-DUSE_LIBSONIC=OFF', '-DUSE_LIBPCAUDIO=OFF']
headers = args.work / 'headers'
headers.mkdir(exist_ok=True)
shutil.copyfile(source / 'src/include/espeak-ng/speak_lib.h', headers / 'speak_lib.h')
(headers / 'module.modulemap').write_text('module EspeakNG { header "speak_lib.h" export * }\n')
libraries = []
for name, sdk in [('mac', 'macosx'), ('sim', 'iphonesimulator'), ('device', 'iphoneos')]:
    build = args.work / name
    flags = ['-DCMAKE_OSX_ARCHITECTURES=arm64']
    if name != 'mac':
        flags += ['-DCMAKE_SYSTEM_NAME=iOS', '-DCMAKE_OSX_SYSROOT=' + sdk, '-DCMAKE_OSX_DEPLOYMENT_TARGET=18.0', '-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY']
    else:
        flags += ['-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0']
    run('cmake', '-S', source, '-B', build, *common, *flags)
    run('cmake', '--build', build, '--target', 'espeak-ng' if name != 'mac' else 'all', '--parallel', '4')
    combined = build / 'libEspeakNG.a'
    run('xcrun', 'libtool', '-static', '-o', combined, build / 'src/libespeak-ng/libespeak-ng.a', build / 'src/ucd-tools/libucd.a')
    framework = build / 'EspeakNG.framework'
    (framework / 'Headers').mkdir(parents=True, exist_ok=True)
    (framework / 'Modules').mkdir(exist_ok=True)
    sdk_path = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
    target = {'mac': 'arm64-apple-macos14.0', 'sim': 'arm64-apple-ios18.0-simulator', 'device': 'arm64-apple-ios18.0'}[name]
    run('xcrun', '--sdk', sdk, 'clang', '-dynamiclib', '-target', target, '-isysroot', sdk_path,
        '-Wl,-force_load,' + str(combined), '-install_name', '@rpath/EspeakNG.framework/EspeakNG', '-o', framework / 'EspeakNG')
    shutil.copyfile(headers / 'speak_lib.h', framework / 'Headers/speak_lib.h')
    (framework / 'Modules/module.modulemap').write_text('framework module EspeakNG { umbrella header "speak_lib.h" export * }\n')
    (framework / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.espeak.harbour.phonemizer', 'CFBundleName': 'EspeakNG', 'CFBundleExecutable': 'EspeakNG', 'CFBundlePackageType': 'FMWK', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.52.0'}))
    libraries += ['-framework', str(framework)]
vendor.mkdir(parents=True, exist_ok=True)
if artifact.exists(): shutil.rmtree(artifact)
run('xcodebuild', '-create-xcframework', *libraries, '-output', artifact)
data = resources / 'espeak-ng-data'
data.mkdir(parents=True, exist_ok=True)
compiled = args.work / 'mac/espeak-ng-data'
for filename in ['phondata', 'phondata-manifest', 'phonindex', 'phontab', 'intonations', 'en_dict', 'fr_dict']:
    if (compiled / filename).exists(): shutil.copyfile(compiled / filename, data / filename)
for folder in ['lang', 'voices']:
    shutil.copytree(compiled / folder, data / folder, dirs_exist_ok=True)
print('Prepared', artifact, 'and bundled English/French phonemizer data.')
