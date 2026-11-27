#!/usr/bin/env python3
"""Apply pinned SwiftFormat layout plus compiler-aware spacing before guards/returns."""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.64.6'
SWIFTFORMAT = str(ROOT / 'build/tools/swiftformat') if (ROOT / 'build/tools/swiftformat').exists() else shutil.which('swiftformat')
ENV = os.environ.copy()
if Path('/Applications/Xcode.app/Contents/Developer').exists():
    ENV.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, check=True, text=True, capture_output=True, env=ENV, **kwargs)


def statement_spacing(source: str) -> str:
    """Use Swift parser locations, never search source text for keywords inside strings."""
    with tempfile.TemporaryDirectory(prefix='harbour-format-') as directory:
        path = Path(directory) / 'Input.swift'
        path.write_text(source)
        result = run(['xcrun', 'swiftc', '-frontend', '-dump-parse', '-swift-version', '5', str(path)])
    tree = result.stdout + result.stderr
    lines = source.splitlines(keepends=True)
    starts: set[int] = set()
    guards: set[int] = set()
    nodes = []
    pattern = re.compile(r'^( *)(\((\w+)[^\n]*?range=\[[^\n]*?:(\d+):(\d+) - line:(\d+):\d+\])', re.M)
    for match in pattern.finditer(tree):
        indent, _, kind, start, column, end = match.groups()
        start, column, end = int(start), int(column), int(end)
        if kind == 'guard_stmt':
            guards.add(end)
        nodes.append((len(indent), kind, start, column))
    for depth, kind, start, column in nodes:
        index = start - 1
        if not 0 < index < len(lines):
            continue
        text = lines[index].lstrip()
        explicit = kind in {'guard_stmt', 'return_stmt', 'throw_stmt', 'break_stmt', 'continue_stmt'}
        top_level = depth == 2 and kind in {'struct_decl', 'class_decl', 'enum_decl', 'extension_decl', 'func_decl', 'var_decl', 'typealias'}
        if not explicit and not top_level:
            continue
        # A return in a one-line closure is not a standalone statement to separate.
        if explicit and not re.match(r'(guard|return|throw|break|continue)\b', text):
            continue
        previous = lines[index - 1].strip()
        if not previous or previous.endswith(('{', ':')) or previous.startswith('#'):
            continue
        if kind == 'guard_stmt' and index in guards:
            continue  # Keep consecutive guards as a group.
        # Keep documentation/attributes attached to the declaration they describe.
        if top_level and previous.startswith(('//', '/*', '*', '@')):
            continue
        starts.add(index)
    return ''.join(('\n' if index in starts else '') + line for index, line in enumerate(lines))


def formatted(source: str, path: Path) -> str:
    layout = run([SWIFTFORMAT, 'stdin', '--config', str(ROOT / '.swiftformat'), '--stdin-path', str(path), '--quiet'], input=source).stdout
    return statement_spacing(layout)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Do not modify files; fail if formatting differs.')
    parser.add_argument('--self-test', action='store_true', help='Check spacing, literal preservation and idempotence.')
    args = parser.parse_args()
    if not SWIFTFORMAT or run([SWIFTFORMAT, '--version']).stdout.strip() != VERSION:
        parser.error(f'Run python3 scripts/prepare-format.py for SwiftFormat {VERSION}; other versions are rejected.')
    if args.self_test:
        fixture = ROOT / 'scripts/format-fixtures/spacing.swift'
        source = fixture.read_text()
        once = formatted(source, fixture)
        assert formatted(once, fixture) == once, 'Formatting must be idempotent'
        assert '\n\n        guard let value' in once
        assert '\n\n        return doubled' in once
        assert 'guard return\n        let untouched = "return"' in once
        assert 'let doubled = value * 2' in once
        print('PASS: guard/return spacing, multiline literals and idempotence')
        return
    names = run(['git', '-C', str(ROOT), 'ls-files', '-z', '*.swift']).stdout.split('\0')
    paths = [ROOT / name for name in names if name and not name.startswith('docs/evaluation/')]
    def process(path: Path) -> str | None:
        before = path.read_text()
        after = formatted(before, path)
        if before == after:
            return None
        if not args.check:
            path.write_text(after)
        return str(path.relative_to(ROOT))
    with ThreadPoolExecutor(max_workers=4) as pool:
        changed = [name for name in pool.map(process, paths) if name]
    for name in changed:
        print(name)
    print(f'{len(paths)} Swift files checked; {len(changed)} ' + ('need formatting' if args.check else 'formatted') + '. Frozen evaluation snapshots excluded.')
    if args.check and changed:
        raise SystemExit(1)


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr or error.stdout or str(error)) from error
