#!/usr/bin/env python3
"""Prepare or build Harbour with xtool, without account login or device installation."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def prepare_info() -> Path:
    """Reuse Xcode's source metadata and version settings instead of duplicating them."""
    with (ROOT / 'Harbour/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    project = (ROOT / 'Harbour.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    configurations = re.findall(r'buildSettings\s*=\s*\{([^{}]*)\}', project)
    app_settings = [value for value in configurations if re.search(r'\bPRODUCT_NAME\s*=\s*Harbour\s*;', value)]
    shared_settings = [value for value in configurations if not re.search(r'\bPRODUCT_NAME\s*=', value)]
    if not app_settings:
        raise ValueError('Could not locate Harbour app settings in the Xcode project')

    def setting(key: str) -> str:
        pattern = r'\b' + re.escape(key) + r'\s*=\s*([^;]+);'
        values = set(re.findall(pattern, '\n'.join(app_settings)))
        if not values:
            values = set(re.findall(pattern, '\n'.join(shared_settings)))
        if len(values) != 1:
            raise ValueError(f'Expected one consistent Xcode {key} value, found {values}')
        return values.pop().strip().strip('"')

    info.update({
        'CFBundleIdentifier': setting('PRODUCT_BUNDLE_IDENTIFIER'),
        'CFBundleName': setting('PRODUCT_NAME'),
        'CFBundleDisplayName': setting('INFOPLIST_KEY_CFBundleDisplayName'),
        'CFBundleShortVersionString': setting('MARKETING_VERSION'),
        'CFBundleVersion': setting('CURRENT_PROJECT_VERSION'),
        'MinimumOSVersion': setting('IPHONEOS_DEPLOYMENT_TARGET'),
        'UIDeviceFamily': [int(value) for value in setting('TARGETED_DEVICE_FAMILY').split(',')],
        'UISupportedInterfaceOrientations': setting('INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone').split(),
        'UISupportedInterfaceOrientations~ipad': setting('INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad').split(),
        'UIApplicationSceneManifest': {
            'UIApplicationSupportsMultipleScenes': True,
            'UISceneConfigurations': {}
        },
        'UILaunchScreen': {}
    })
    destination = ROOT / 'build/xtool/Info.plist'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps(info, sort_keys=True))
    return destination


def validate_bundle() -> None:
    """Reject a successful build command that produced an incomplete app bundle."""
    app = ROOT / 'xtool/Harbour.app'
    with (app / 'Info.plist').open('rb') as stream:
        packaged = plistlib.load(stream)
    with (ROOT / 'build/xtool/Info.plist').open('rb') as stream:
        expected = plistlib.load(stream)
    for key, value in expected.items():
        if packaged.get(key) != value:
            raise ValueError(f'Packaged Info.plist did not preserve {key}')
    required = [
        'Harbour', 'AppIcon.png', 'PrivacyInfo.xcprivacy',
        'en.lproj/Localizable.strings', 'en.lproj/InfoPlist.strings',
        'fr-CA.lproj/Localizable.strings', 'fr-CA.lproj/InfoPlist.strings',
        'Frameworks/llama.framework/llama',
        'Frameworks/llama.framework/PrivacyInfo.xcprivacy'
    ]
    for resource in required:
        if not (app / resource).is_file():
            raise ValueError(f'Missing packaged resource: {resource}')
    for binary in ['Harbour', 'Frameworks/llama.framework/llama']:
        with (app / binary).open('rb') as stream:
            header = stream.read(12)
        if len(header) != 12 or struct.unpack('<II', header[:8]) != (0xFEEDFACF, 0x0100000C):
            raise ValueError(f'Expected an arm64 Mach-O binary: {binary}')
    print('Validated arm64 app, llama framework, privacy manifests, and main-bundle localizations.')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
    parser.add_argument('--prepare-only', action='store_true', help='Prepare runtime and plist without compiling or requiring an SDK.')
    parser.add_argument('--runtime-archive', type=Path, help='Use a previously downloaded pinned llama release ZIP.')
    parser.add_argument('--xtool', default='xtool', help='xtool executable path.')
    args = parser.parse_args()
    if not args.prepare_only:
        if sys.platform == 'win32':
            parser.error('Run the build inside WSL or Linux, or on macOS. Windows can run --prepare-only.')
        executable = shutil.which(args.xtool)
        if executable is None:
            parser.error('xtool is unavailable. Install xtool 1.21.0 and Swift 6.4 first; see docs/xtool.md.')
        if sys.platform != 'darwin':
            status = subprocess.run([executable, 'sdk', 'status'], check=True, capture_output=True, text=True)
            if 'Darwin SDK is installed' not in status.stdout:
                print('Apple SDK is missing. Run: xtool sdk install /path/to/Xcode_27.xip', file=sys.stderr)
                return 2
    command = [sys.executable, str(ROOT / 'scripts/prepare-device-runtime.py')]
    if args.runtime_archive is not None:
        command += ['--archive', str(args.runtime_archive.resolve())]
    subprocess.run(command, cwd=ROOT, check=True)
    destination = prepare_info()
    print(f'Prepared app metadata: {destination.relative_to(ROOT)}')
    if args.prepare_only:
        print('Preparation complete. No iOS compilation or device validation was performed.')
        return 0
    environment = dict(os.environ, HARBOUR_DEVICE_RUNTIME='1', HARBOUR_LINUX_RUNTIME='0')
    with destination.open('rb') as stream:
        minimum_os = plistlib.load(stream)['MinimumOSVersion']
    subprocess.run([executable, 'dev', 'build', '--configuration', args.configuration, '--triple', 'arm64-apple-ios' + minimum_os], cwd=ROOT, env=environment, check=True)
    validate_bundle()
    print('Built xtool/Harbour.app. No Apple account provisioning, installation, or upload was requested.')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'xtool build failed: {error}', file=sys.stderr)
        raise SystemExit(1)
