#!/usr/bin/env python3
"""Archive/export Harbour, with an explicit opt-in for internal-only TestFlight uploads."""
import argparse
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--team-id', default=os.environ.get('HARBOUR_TEAM_ID'))
    parser.add_argument('--output', type=Path, default=ROOT / 'build/testflight')
    parser.add_argument('--archive', type=Path, help='Reuse this archive with --skip-archive.')
    parser.add_argument('--skip-archive', action='store_true')
    parser.add_argument('--build-number', help='New numeric build number; required after uploading build 1.')
    parser.add_argument('--upload', action='store_true', help='Upload to Apple for INTERNAL TestFlight only.')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Z0-9]{10}', args.team_id or ''):
        parser.error('Provide --team-id or HARBOUR_TEAM_ID (10 uppercase letters/digits).')
    if args.build_number and not re.fullmatch(r'[1-9][0-9]*', args.build_number):
        parser.error('--build-number must be a positive integer.')
    if args.skip_archive and args.build_number:
        parser.error('--build-number cannot change an existing archive.')
    if args.archive and not args.skip_archive:
        parser.error('--archive is only for --skip-archive.')
    output = args.output.expanduser().resolve()
    archive = args.archive.expanduser().resolve() if args.archive else output / 'Harbour.xcarchive'
    if not args.skip_archive and archive.exists():
        parser.error('Archive already exists; choose a new --output or use --skip-archive.')
    if args.skip_archive and not (archive / 'Info.plist').exists():
        parser.error('The archive does not exist.')
    if not (ROOT / 'HarbourRuntime/Vendor/llama.xcframework/Info.plist').exists():
        parser.error('Run bash scripts/prepare-runtime.sh first.')
    output.mkdir(parents=True, exist_ok=True)

    def run(command, log_name):
        print('Running:', subprocess.list2cmdline(command), flush=True)
        log = output / log_name
        with log.open('w') as handle:
            result = subprocess.run(command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT)
        if result.returncode:
            print(log.read_text()[-8000:])
            raise SystemExit(f'Failed ({result.returncode}). Full log: {log}')
        print(f'Completed. Log: {log}', flush=True)

    if not args.skip_archive:
        run([sys.executable, str(ROOT / 'scripts/runtime-privacy.py'),
             str(ROOT / 'HarbourRuntime/Vendor/llama.xcframework')], 'runtime-privacy.log')
        command = ['xcodebuild', 'archive', '-project', 'Harbour.xcodeproj', '-scheme', 'Harbour',
                   '-configuration', 'Release', '-destination', 'generic/platform=iOS',
                   '-archivePath', str(archive), '-derivedDataPath', str(output / 'DerivedData'),
                   '-allowProvisioningUpdates', '-jobs', '1', f'DEVELOPMENT_TEAM={args.team_id}']
        if args.build_number:
            command.append(f'CURRENT_PROJECT_VERSION={args.build_number}')
        run(command, 'archive.log')
    info = plistlib.loads((archive / 'Info.plist').read_bytes())['ApplicationProperties']
    if info['CFBundleIdentifier'] != 'com.matteopolak.harbour' or info.get('Team') != args.team_id:
        raise SystemExit('Archive bundle identifier or signing team does not match Harbour.')
    app = archive / 'Products' / info['ApplicationPath']
    if not (app / 'PrivacyInfo.xcprivacy').exists():
        raise SystemExit('Archive is missing the app privacy manifest; rebuild it.')
    options = {'method': 'app-store-connect', 'destination': 'upload' if args.upload else 'export',
               'teamID': args.team_id, 'signingStyle': 'automatic', 'uploadSymbols': True,
               'manageAppVersionAndBuildNumber': False, 'testFlightInternalTestingOnly': True}
    options_file = output / 'ExportOptions.plist'
    options_file.write_bytes(plistlib.dumps(options))
    run(['xcodebuild', '-exportArchive', '-archivePath', str(archive),
         '-exportPath', str(output / 'export'), '-exportOptionsPlist', str(options_file),
         '-allowProvisioningUpdates'], 'upload.log' if args.upload else 'export.log')
    print(f"Harbour {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}): "
          + ('upload accepted; verify processing and tester access in App Store Connect.' if args.upload
             else 'export complete. No upload was requested.'))


if __name__ == '__main__':
    main()
