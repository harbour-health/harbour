"""Reproduce application bugs against exact baseline source, without model inference.

Passing characterization assertions mean the recorded bug is present. This is
an investigation harness, not a replacement for the product's regression gate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

BASE = "5158710fa518816ca14781ca4d7a4c3f459675b8"
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--repository", type=Path, default=HERE.parents[1])
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
repository = args.repository.resolve()
out = args.output.resolve()
assert not out.exists(), "Use a new output directory; preserve previous runs"
out.mkdir(parents=True)
source = out / "source"
source.mkdir()
manifest = json.loads((HERE / "source-manifest.json").read_bytes())
assert manifest["sourceCommit"] == BASE and manifest["canonicalGitBytes"]
for entry in manifest["files"]:
    name = entry["path"]
    relative = Path(name)
    assert not relative.is_absolute() and ".." not in relative.parts
    data = subprocess.check_output(["git", "show", BASE + ":" + name], cwd=repository)
    assert len(data) == entry["bytes"] and hashlib.sha256(data).hexdigest() == entry["sha256"]
    target = source / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
tests = []
for path in sorted((HERE / "core-tests").glob("*.swift")):
    data = path.read_bytes()
    (source / "HarbourCore/Tests/HarbourCoreTests" / path.name).write_bytes(data)
    tests.append({"path": path.name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
assert tests, "No investigation tests found"
env = dict(os.environ, HARBOUR_INVESTIGATION_SOURCE_ROOT=str(source))
command = ["swift", "test", "--package-path", str(source / "HarbourCore"), "--jobs", "4", "--filter", "ReproductionTests"]
started = time.monotonic()
with (out / "swift-test.log").open("xb") as log:
    result = subprocess.run(command, cwd=repository, env=env, stdout=log, stderr=subprocess.STDOUT)
for entry in manifest["files"]:
    assert hashlib.sha256((source / entry["path"]).read_bytes()).hexdigest() == entry["sha256"], "Baseline source changed"
record = {
    "baselineCommit": BASE,
    "canonicalSourceFiles": len(manifest["files"]),
    "baselineFilesUnchangedAfterRun": True,
    "testSources": tests,
    "command": command,
    "exitCode": result.returncode,
    "elapsedSeconds": time.monotonic() - started,
    "logSHA256": hashlib.sha256((out / "swift-test.log").read_bytes()).hexdigest(),
    "noModelInference": True,
    "meaning": "Passing reproduction assertions confirm current defective behavior and controls; they do not mean the bugs are fixed.",
}
(out / "execution.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print(json.dumps(record))
raise SystemExit(result.returncode)
