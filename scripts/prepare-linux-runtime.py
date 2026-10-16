#!/usr/bin/env python3
"""Build a verified, isolated llama.cpp b10549 CPU library for the native Swift evaluator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

BUILD = "b10549"
SOURCE_URL = "https://codeload.github.com/ggml-org/llama.cpp/tar.gz/refs/tags/b10549"
SOURCE_SHA256 = "418ef98f058952c4f2e1fba0f77a73cbbfac2e5bf4146a0dc3202777ed5d9c1f"
ROOT = Path(__file__).resolve().parent.parent

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1_048_576), b""):
            value.update(data)
    return value.hexdigest()

def run(args):
    subprocess.run(args, check=True)

def installed_files(prefix):
    return {str(path.relative_to(prefix)): digest(path)
        for directory in [prefix / "include", prefix / "lib"]
        for path in sorted(directory.rglob("*")) if path.is_file()}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", type=Path, default=ROOT / "build/runtime/linux-b10549")
    parser.add_argument("--source-archive", type=Path, help="Use an existing source archive after its SHA-256 check.")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("Run this helper on Linux, preferably with scripts/model-eval/Dockerfile.")
    if args.jobs < 1 or args.jobs > 16:
        parser.error("--jobs must be 1 to 16")
    for executable in ["cmake", "pkg-config"]:
        if shutil.which(executable) is None:
            parser.error(f"{executable} is required; use the isolated evaluator Docker image.")
    prefix = args.prefix.resolve()
    marker = prefix / "harbour-runtime.json"
    library = prefix / "lib/libllama.so"
    if marker.is_file() and library.is_file():
        metadata = json.loads(marker.read_text())
        if metadata.get("sourceSHA256") == SOURCE_SHA256 and metadata.get("librarySHA256") == digest(library) and metadata.get("installedFilesSHA256") == installed_files(prefix):
            print(f"Pinned CPU runtime already prepared: {prefix}")
            return
        raise RuntimeError("Existing isolated runtime failed provenance verification; choose a new --prefix.")
    if prefix.exists() and any(prefix.iterdir()):
        raise RuntimeError(f"Refusing to overwrite an unfamiliar runtime prefix: {prefix}")
    cache = ROOT / "build/runtime"
    cache.mkdir(parents=True, exist_ok=True)
    archive = args.source_archive.resolve() if args.source_archive else cache / "llama-b10549-source.tar.gz"
    if not archive.exists():
        if args.source_archive:
            raise RuntimeError(f"Missing supplied source archive: {archive}")
        with urllib.request.urlopen(SOURCE_URL, timeout=60) as source, archive.open("xb") as destination:
            shutil.copyfileobj(source, destination, length=1_048_576)
    if digest(archive) != SOURCE_SHA256:
        raise RuntimeError(f"Pinned source SHA-256 mismatch: {archive}")
    with tempfile.TemporaryDirectory(prefix="llama-linux-build-", dir=cache) as temporary:
        work = Path(temporary)
        source = work / "source"
        source.mkdir()
        with tarfile.open(archive) as package:
            for member in package.getmembers():
                relative = Path(member.name)
                if relative.is_absolute() or ".." in relative.parts:
                    raise RuntimeError(f"Unsafe source archive path: {member.name}")
            package.extractall(source, filter="data")
        source_root = next(source.iterdir())
        build = work / "build"
        configure = ["cmake", "-S", str(source_root), "-B", str(build), "-DCMAKE_BUILD_TYPE=Release",
            f"-DCMAKE_INSTALL_PREFIX={prefix}", "-DCMAKE_INSTALL_LIBDIR=lib", "-DBUILD_SHARED_LIBS=ON",
            "-DLLAMA_BUILD_APP=OFF", "-DLLAMA_BUILD_COMMON=OFF", "-DLLAMA_BUILD_TESTS=OFF",
            "-DLLAMA_BUILD_EXAMPLES=OFF", "-DLLAMA_BUILD_TOOLS=OFF", "-DLLAMA_BUILD_SERVER=OFF",
            "-DLLAMA_BUILD_MTMD=OFF", "-DGGML_METAL=OFF", "-DGGML_CUDA=OFF", "-DGGML_VULKAN=OFF",
            "-DGGML_BLAS=OFF", "-DGGML_OPENMP=OFF", "-DGGML_NATIVE=OFF", "-DGGML_RPC=OFF"]
        run(configure)
        run(["cmake", "--build", str(build), "--parallel", str(args.jobs)])
        run(["cmake", "--install", str(build)])
    if not library.is_file() or not (prefix / "lib/pkgconfig/llama.pc").is_file():
        raise RuntimeError("The pinned build did not install libllama.so and llama.pc.")
    metadata = {"runtimeBuild": BUILD, "sourceSHA256": SOURCE_SHA256, "sourceURL": SOURCE_URL,
        "librarySHA256": digest(library), "installedFilesSHA256": installed_files(prefix), "platform": platform.platform(), "cmakeArguments": configure,
        "compilerVersion": subprocess.check_output(["cc", "--version"], text=True).splitlines()[0],
        "cmakeVersion": subprocess.check_output(["cmake", "--version"], text=True).splitlines()[0]}
    marker.write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Prepared pinned CPU runtime: {prefix}")

if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Linux runtime preparation failed: {error}")
