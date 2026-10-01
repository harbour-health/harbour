#!/usr/bin/env python3
"""Validate and export the dedicated App Store XCTest captures; never resize PNGs."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from PIL import Image, ImageDraw

result, output = map(Path, sys.argv[1:3])
locale = sys.argv[3]
summary = json.loads(subprocess.check_output([
    "xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)
]))
if summary.get("failedTests", 0) or summary.get("passedTests") != 1 or summary.get("totalTestCount") != 1 or summary.get("result") != "Passed":
    raise SystemExit("Screenshot test did not pass exactly once; refusing to publish a partial set.")
configurations = summary.get("devicesAndConfigurations", [])
if len(configurations) != 1:
    raise SystemExit("Expected one simulator configuration.")
device = configurations[0]["device"]
if device.get("modelName") != "iPhone 17 Pro Max" or device.get("osVersion") != "26.5" or device.get("platform") != "iOS Simulator":
    raise SystemExit(f"Unexpected capture device: {device}")
expected_test = {"en-CA": "testCaptureEnglish", "fr-CA": "testCaptureFrench"}.get(locale)
if expected_test is None:
    raise SystemExit("Unsupported locale.")
names = ["01-today", "02-records", "03-medicines", "04-readings", "05-symptoms", "06-visits", "07-visit-notes", "08-appointment-preparation", "09-timeline", "10-chat"]
entries = {}
with tempfile.TemporaryDirectory(prefix="harbour-store-export-") as temporary:
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", temporary], check=True, stdout=subprocess.DEVNULL)
    for test in json.loads((Path(temporary) / "manifest.json").read_text()):
        if "HarbourAppStoreScreenshotTests" not in test["testIdentifier"]:
            continue
        if expected_test not in test["testIdentifier"]:
            raise SystemExit("Capture test does not match the requested locale.")
        for attachment in test["attachments"]:
            match = re.match(r"appstore-(\d{2}-[a-z-]+)_", attachment["suggestedHumanReadableName"])
            if not match or not attachment["exportedFileName"].endswith(".png"):
                continue
            name = match[1]
            if name not in names or name in entries:
                raise SystemExit(f"Unexpected or duplicate screenshot: {name}")
            source = Path(temporary) / attachment["exportedFileName"]
            with Image.open(source) as image:
                image.load()
                if image.size != (1320, 2868):
                    raise SystemExit(f"Wrong native dimensions for {name}: {image.size}")
                # Store PNGs require no alpha; pixels retain their native size and colour.
                rgb = image.convert("RGB")
                rgb.save(output / (name + ".png"))
            entries[name] = {key: attachment.get(key) for key in ("deviceName", "deviceId", "timestamp", "suggestedHumanReadableName")}
            entries[name].update(file=name + ".png", test=test["testIdentifier"], width=1320, height=2868, mode="RGB", sha256=hashlib.sha256((output / (name + ".png")).read_bytes()).hexdigest())
if set(entries) != set(names):
    raise SystemExit(f"Incomplete set; missing {sorted(set(names) - set(entries))}")
manifest = {
    "locale": locale, "appearance": "Light", "deviceType": "iPhone 17 Pro Max", "runtime": "iOS 26.5",
    "resultBundle": str(result), "simulator": device, "xcodeVersion": (output / "run/xcode-version.txt").read_text().strip(),
    "fixture": "DEBUG-only --app-store-screenshots; fictional saved records, manual visit notes, empty chat; no model requests or model downloads",
    "fixtureDate": "2026-10-01T13:00:00Z", "statusBarTime": "9:41", "dateHeading": "Actual capture date",
    "testResult": summary["result"], "captures": [entries[name] for name in names]
}
(output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
sheet = Image.new("RGB", (1600, 1510), "#eeeeee")
draw = ImageDraw.Draw(sheet)
for index, name in enumerate(names):
    with Image.open(output / (name + ".png")) as shot:
        shot.thumbnail((300, 652))
        x, y = 10 + (index % 5) * 320, 14 + (index // 5) * 750
        sheet.paste(shot, (x, y))
        draw.text((x, y + 665), name, fill="#181818")
sheet.save(output / "contact-sheet.jpg", quality=92)
print(f"Validated and exported {len(entries)} RGB PNGs at 1320 × 2868.")
