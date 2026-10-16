#!/usr/bin/env python3
"""Cache the exact production GGUF files after size and SHA-256 verification."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

MODELS = {
    "small": ("Qwen/Qwen2.5-0.5B-Instruct-GGUF", "9217f5db79a29953eb74d5343926648285ec7e67", "qwen2.5-0.5b-instruct-q4_k_m.gguf", 491400032, "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"),
    "balanced": ("Qwen/Qwen2.5-1.5B-Instruct-GGUF", "91cad51170dc346986eccefdc2dd33a9da36ead9", "qwen2.5-1.5b-instruct-q4_k_m.gguf", 1117320736, "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"),
    "qwen35": ("unsloth/Qwen3.5-2B-GGUF", "f6d5376be1edb4d416d56da11e5397a961aca8ae", "Qwen3.5-2B-Q4_K_M.gguf", 1280835840, "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223"),
}

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1048576), b""): h.update(chunk)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", nargs="+", choices=MODELS, default=list(MODELS))
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--verification-markers", action="store_true", help="Also create the app's verified markers for simulator test preloading.")
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    results = []
    for name in args.models:
        repo, revision, filename, size, sha = MODELS[name]
        path = args.directory / filename
        url = f"https://huggingface.co/{repo}/resolve/{revision}/{filename}"
        if not path.exists():
            partial = args.directory / (filename + ".eval-download.partial")
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Harbour-Evaluation/1"}), timeout=60) as src, partial.open("wb") as dst:
                while chunk := src.read(1048576): dst.write(chunk)
            if partial.stat().st_size != size or digest(partial) != sha:
                raise ValueError(f"Pinned model failed size/SHA-256 verification: {filename}")
            partial.replace(path)
        if path.stat().st_size != size or digest(path) != sha:
            raise ValueError(f"Cached model failed size/SHA-256 verification: {filename}")
        if args.verification_markers:
            path.with_suffix(path.suffix + ".verified").write_text(sha, encoding="utf-8")
        item = dict(model=name, repository=repo, revision=revision, url=url, filename=filename, bytes=size, sha256=sha, verified=True)
        results.append(item)
        print(json.dumps(item), flush=True)
    (args.directory / "model-provenance.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__": main()
