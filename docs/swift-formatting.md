# Swift formatting

## What it is

A pinned, repository-wide Swift layout workflow adds consistent indentation, wrapping and blank lines between scopes and before standalone guards/returns. The bulk formatting change lives in its own commit, listed in `.git-blame-ignore-revs`.

## How it works

Run `python3 scripts/prepare-format.py` once, then `python3 scripts/format.py`. `--check` reports differences without modifying files; `--self-test` checks statement spacing, literal preservation and idempotence. CI runs the same checks.

The first pass uses SwiftFormat 0.64.6 with an explicit whitespace/layout-only rule list in `.swiftformat`. It does not enable API migrations, declaration reordering, redundant-expression removal or test-framework conversion. The second pass obtains statement source ranges from `swiftc -frontend -dump-parse`, adding separation before standalone guards, returns, throws and loop exits, and top-level declarations. Consecutive guards stay together; the built-in rule separates the guard group from subsequent variables. The script never searches prompt/string contents for source keywords. Statements inside compiler-inactive conditional branches still receive SwiftFormat's normal layout; extra statement grouping follows the active host parse.

Only tracked Swift source is formatted. Historical `docs/evaluation/` Swift snapshots are deliberately excluded because they are frozen provenance, not maintained source; changing them would invalidate comparisons/hashes. Vendor code, build products and downloaded assets are excluded. All maintained app, package, test, widget and script Swift files are included.

## How to change it

Edit `.swiftformat` for base layout and `scripts/format.py` for statement grouping. Extend `scripts/format-fixtures/spacing.swift` and the self-test when changing grouping, especially around multiline literals and inline guards. Run twice and verify `--check` is clean. Keep future mass-formatting changes in separate commits and append their full hashes to `.git-blame-ignore-revs` in a subsequent bookkeeping commit.

GitHub understands the standard ignore file. For local Git, run `git config blame.ignoreRevsFile .git-blame-ignore-revs`, or use `git blame --ignore-revs-file .git-blame-ignore-revs PATH`. Do not add functional commits to the ignore list.

## Configuration

`prepare-format.py` downloads the official macOS 0.64.6 archive, checks SHA-256 `70e6b2057647fb1c54d620ebbb6649274de56534c57f91f67461a129ebaaba3e`, and installs into ignored `build/tools/`. The formatter uses that binary, otherwise a matching PATH installation; other versions fail. No downloaded binary is committed. Four workers process source files. The script respects `DEVELOPER_DIR`, defaulting to `/Applications/Xcode.app/Contents/Developer` if present, without changing the global Xcode selection.

## Dependencies

Python 3 standard library, Git, Xcode's Swift compiler and the official [SwiftFormat](https://github.com/nicklockwood/SwiftFormat/tree/0.64.6) release. Network access is required only for the initial tool installation, not formatting/checking.
