#!/usr/bin/env python3
"""Add the locally audited llama file-metadata declaration to each framework slice."""
import argparse
import plistlib
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('framework', type=Path)
args = parser.parse_args()
frameworks = list(args.framework.glob('*/llama.framework'))
if not frameworks:
    parser.error('No llama.framework slices found.')
manifest = {'NSPrivacyTracking': False, 'NSPrivacyTrackingDomains': [], 'NSPrivacyCollectedDataTypes': [],
            'NSPrivacyAccessedAPITypes': [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryFileTimestamp',
                                          'NSPrivacyAccessedAPITypeReasons': ['C617.1']}]}
for framework in frameworks:
    resources = framework / 'Resources' if (framework / 'Versions').exists() else framework
    (resources / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(manifest))
print(f'Updated privacy manifests in {len(frameworks)} runtime slices.')
