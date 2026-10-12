#!/usr/bin/env python3
"""Prepare the pinned iPhone-only llama runtime for xtool without Xcode.

The normal llama.xcframework remains owned by prepare-runtime.sh. This helper
uses a separate, ignored llama-device.xcframework and never extracts Mac links.
"""
import argparse
import hashlib
import json
import os
import plistlib
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.request
import uuid
import zipfile


BUILD = "b10549"
ARCHIVE_NAME = f"llama-{BUILD}-xcframework.zip"
ARCHIVE_URL = f"https://github.com/ggml-org/llama.cpp/releases/download/{BUILD}/{ARCHIVE_NAME}"
ARCHIVE_SHA256 = "636709d4a7b49ac7f2ed6dc8a4de3f278c257cac7248fe40d6a513f671e4bff4"
ARCHIVE_BYTES = 79_011_953
BINARY_SHA256 = "f8c32f64a9c74dda29978b9b7049f3484fd528e12229a80c2664f86c705aff9f"
MODULEMAP_SHA256 = "b5651903a342dc59fb4fe16ff9cc82ba4d08fdb142458aeacf516e7c31c15f15"
PREFIX = "build-apple/llama.xcframework/"
DEVICE = "ios-arm64"
MARKER = ".harbour-device-runtime.json"
ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "HarbourRuntime" / "Vendor"
TARGET = VENDOR / "llama-device.xcframework"
CACHE = ROOT / "build" / "runtime" / ARCHIVE_NAME


def within_workspace(path):
    resolved = path.resolve()
    if not resolved.is_relative_to(ROOT):
        raise RuntimeError(f"Path escapes the workspace: {path}")
    return resolved


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1_048_576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_archive(path):
    if path.stat().st_size != ARCHIVE_BYTES or sha256(path) != ARCHIVE_SHA256:
        raise RuntimeError(f"Pinned runtime archive failed size/SHA-256 verification: {path}")


def archive_for(offline_archive):
    if offline_archive is not None:
        archive = offline_archive.resolve()
        validate_archive(archive)
        return archive
    within_workspace(CACHE)
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    if CACHE.exists():
        validate_archive(CACHE)
        return CACHE
    descriptor, name = tempfile.mkstemp(prefix="llama-download-", suffix=".partial", dir=CACHE.parent)
    partial = Path(name)
    try:
        print(f"Downloading {ARCHIVE_URL}", flush=True)
        request = urllib.request.Request(ARCHIVE_URL, headers={"User-Agent": "HarbourRuntimePrep/1"})
        with os.fdopen(descriptor, "wb") as output, urllib.request.urlopen(request, timeout=60) as response:
            shutil.copyfileobj(response, output, length=1_048_576)
        validate_archive(partial)
        os.replace(partial, CACHE)
    finally:
        if partial.exists():
            within_workspace(partial).unlink()
    return CACHE


def regular_files(directory):
    files = {}
    for path in directory.rglob("*"):
        resolved = within_workspace(path)
        if not resolved.is_relative_to(directory.resolve()) or path.is_symlink():
            raise RuntimeError(f"Runtime contains a link or escaped path: {path}")
        if path.is_file() and path != directory / MARKER:
            files[path.relative_to(directory).as_posix()] = sha256(path)
    return files


def validate_device(directory):
    info = plistlib.loads((directory / "Info.plist").read_bytes())
    libraries = info.get("AvailableLibraries", [])
    if len(libraries) != 1:
        raise RuntimeError("Device runtime must contain exactly one iOS arm64 slice.")
    library = libraries[0]
    required = {"LibraryIdentifier": DEVICE, "LibraryPath": "llama.framework", "SupportedPlatform": "ios",
                "SupportedArchitectures": ["arm64"]}
    if any(library.get(key) != value for key, value in required.items()) or library.get("SupportedPlatformVariant"):
        raise RuntimeError("Runtime slice does not describe an iPhone arm64 framework.")
    framework = directory / DEVICE / "llama.framework"
    if sha256(framework / "llama") != BINARY_SHA256:
        raise RuntimeError("The pinned iPhone runtime binary failed verification.")
    if sha256(framework / "Modules" / "module.modulemap") != MODULEMAP_SHA256:
        raise RuntimeError("The pinned llama module map failed verification.")
    framework_info = plistlib.loads((framework / "Info.plist").read_bytes())
    if framework_info.get("CFBundleExecutable") != "llama" or framework_info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise RuntimeError("The framework is not the expected iPhone runtime.")


def read_owned_marker(directory):
    within_workspace(directory)
    marker = json.loads((directory / MARKER).read_text(encoding="utf-8"))
    if marker.get("formatVersion") != 1 or marker.get("runtimeBuild") != BUILD or marker.get("archiveSHA256") != ARCHIVE_SHA256:
        raise RuntimeError("Existing device runtime is not owned by this preparation helper.")
    recorded = marker.get("files")
    if not isinstance(recorded, dict) or not recorded:
        raise RuntimeError("Device runtime ownership marker has no file manifest.")
    actual = regular_files(directory)
    if set(actual) != set(recorded):
        raise RuntimeError("Device runtime contains missing or unrecognized files; leaving it untouched.")
    return actual == recorded


def refresh_privacy(directory):
    subprocess.run([sys.executable, str(ROOT / "scripts" / "runtime-privacy.py"), str(directory)], check=True)


def write_marker(directory):
    metadata = {"formatVersion": 1, "runtimeBuild": BUILD, "archiveSHA256": ARCHIVE_SHA256,
                "source": ARCHIVE_URL, "files": regular_files(directory)}
    temporary = directory / f"{MARKER}.{uuid.uuid4().hex}.tmp"
    temporary.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, directory / MARKER)


def extract_device(archive, stage):
    with zipfile.ZipFile(archive) as source:
        seen = set()
        for entry in source.infolist():
            parts = PurePosixPath(entry.filename).parts
            if entry.filename.startswith("/") or "\\" in entry.filename or ".." in parts or (parts and ":" in parts[0]):
                raise RuntimeError(f"Unsafe archive path: {entry.filename}")
            if not entry.filename.startswith(PREFIX + DEVICE + "/"):
                continue
            relative = PurePosixPath(entry.filename[len(PREFIX):])
            if relative.as_posix() in seen:
                raise RuntimeError(f"Duplicate archive path: {entry.filename}")
            seen.add(relative.as_posix())
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise RuntimeError(f"Unexpected link in iPhone slice: {entry.filename}")
            destination = stage.joinpath(*relative.parts)
            within_workspace(destination)
            if entry.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with source.open(entry) as input_stream, destination.open("xb") as output:
                    shutil.copyfileobj(input_stream, output, length=1_048_576)
        info = plistlib.loads(source.read(PREFIX + "Info.plist"))
        info["AvailableLibraries"] = [item for item in info["AvailableLibraries"] if item["LibraryIdentifier"] == DEVICE]
        (stage / "Info.plist").write_bytes(plistlib.dumps(info))
    validate_device(stage)


def remove_owned_temporary(directory):
    resolved = within_workspace(directory)
    vendor = within_workspace(VENDOR)
    if resolved.parent != vendor or not directory.name.startswith(".llama-device."):
        raise RuntimeError(f"Refusing to remove an unexpected runtime directory: {directory}")
    regular_files(directory)  # Verify all resolved descendants before recursive deletion on Windows.
    shutil.rmtree(resolved)


def prepare(args):
    within_workspace(VENDOR)
    within_workspace(TARGET)
    VENDOR.mkdir(parents=True, exist_ok=True)
    exists = os.path.lexists(TARGET)
    if exists:
        intact = read_owned_marker(TARGET)
        if not args.refresh:
            if not intact:
                raise RuntimeError("Device runtime failed integrity verification; rerun with --refresh to replace this owned artifact.")
            validate_device(TARGET)
            refresh_privacy(TARGET)
            write_marker(TARGET)
            print(f"Pinned iPhone runtime already prepared: {TARGET}")
            return
    archive = archive_for(args.archive)
    stage = VENDOR / f".llama-device.{uuid.uuid4().hex}.tmp"
    stage.mkdir()
    backup = None
    try:
        extract_device(archive, stage)
        refresh_privacy(stage)
        write_marker(stage)
        if not read_owned_marker(stage):
            raise RuntimeError("Newly prepared device runtime failed its file manifest verification.")
        if exists:
            backup = VENDOR / f".llama-device.{uuid.uuid4().hex}.backup"
            os.replace(TARGET, backup)
        try:
            os.replace(stage, TARGET)
        except BaseException:
            if backup is not None and not os.path.lexists(TARGET):
                os.replace(backup, TARGET)
                backup = None
            raise
        if backup is not None:
            remove_owned_temporary(backup)
        print(f"Prepared {BUILD} iPhone runtime: {TARGET}")
    finally:
        if stage.exists():
            remove_owned_temporary(stage)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use an existing archive after verifying its pinned size and SHA-256.")
    parser.add_argument("--refresh", action="store_true", help="Replace an existing artifact owned by this helper after preparing a verified replacement.")
    args = parser.parse_args()
    try:
        prepare(args)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Runtime preparation failed: {error}\n")


if __name__ == "__main__":
    main()
