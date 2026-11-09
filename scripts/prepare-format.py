#!/usr/bin/env python3
"""Install the pinned official macOS SwiftFormat binary into ignored build/tools."""
import hashlib
import io
from pathlib import Path
import stat
import urllib.request
import zipfile

VERSION = '0.64.6'
DIGEST = '70e6b2057647fb1c54d620ebbb6649274de56534c57f91f67461a129ebaaba3e'
root = Path(__file__).resolve().parents[1]
data = urllib.request.urlopen(f'https://github.com/nicklockwood/SwiftFormat/releases/download/{VERSION}/swiftformat.zip', timeout=60).read()
if hashlib.sha256(data).hexdigest() != DIGEST:
    raise SystemExit('SwiftFormat archive checksum mismatch; nothing installed.')
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    candidates = [name for name in archive.namelist() if Path(name).name == 'swiftformat' and not name.startswith('__MACOSX/')]
    if len(candidates) != 1:
        raise SystemExit('Unexpected SwiftFormat archive contents.')
    executable = archive.read(candidates[0])
destination = root / 'build/tools/swiftformat'
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(executable)
destination.chmod(destination.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
print(f'Installed SwiftFormat {VERSION}: {destination}')
