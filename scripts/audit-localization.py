#!/usr/bin/env python3
"""Check Harbour's catalogs and literal localization calls without third-party tools.

This is a source/catalog consistency check. It cannot prove runtime localization,
SwiftUI overload selection, plural grammar, generated text, or visual layout.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import json
from pathlib import Path
import plistlib
import re
import sys


@dataclass
class Literal:
    start: int
    end: int
    text: str
    line: int
    interpolated: bool = False


def decode_string(value: str) -> str:
    """Decode the escape forms used in the checked-in Swift/.strings files."""
    escapes = {'n': '\n', 'r': '\r', 't': '\t', '0': '\0', '"': '"', '\\': '\\'}
    def replacement(match: re.Match[str]) -> str:
        item = match.group(1)
        if item.startswith('u{'):
            return chr(int(item[2:-1], 16))
        if item.startswith('U'):
            return chr(int(item[1:], 16))
        if item not in escapes:
            raise ValueError(f'Unsupported escape: \\{item}')
        return escapes[item]
    return re.sub(r'\\(u\{[0-9a-fA-F]+\}|U[0-9a-fA-F]{4}|.)', replacement, value)


def read_catalog(path: Path) -> dict[str, str]:
    text = path.read_text(encoding='utf-8')
    pattern = re.compile(r'\s*(?:/\*.*?\*/|//[^\n]*(?:\n|$))', re.S)
    entry = re.compile(r'\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;', re.S)
    values: dict[str, str] = {}
    cursor = 0
    while cursor < len(text):
        comment = pattern.match(text, cursor)
        if comment:
            cursor = comment.end()
            continue
        match = entry.match(text, cursor)
        if not match:
            if not text[cursor:].strip():
                break
            raise ValueError(f'{path}:{text.count(chr(10), 0, cursor) + 1}: invalid .strings syntax')
        key, value = (decode_string(item) for item in match.groups())
        if key in values:
            raise ValueError(f'{path}: duplicate key {key!r}')
        values[key] = value
        cursor = match.end()
    return values


def swift_literals(source: str) -> list[Literal]:
    """Read quoted strings and skip comments; keep interpolations for human review.

    Parenthesis balancing handles nested quoted values inside interpolation. This
    intentionally does not infer a Swift expression's type or localization key.
    """
    result: list[Literal] = []
    def comment_end(index: int) -> int | None:
        if source.startswith('//', index):
            end = source.find('\n', index + 2)
            return len(source) if end < 0 else end
        if source.startswith('/*', index):
            depth, end = 1, index + 2
            while end < len(source) and depth:
                if source.startswith('/*', end):
                    depth += 1; end += 2
                elif source.startswith('*/', end):
                    depth -= 1; end += 2
                else:
                    end += 1
            return end
        return None
    def read_quoted(start: int) -> int:
        hashes = 0
        while start + hashes < len(source) and source[start + hashes] == '#':
            hashes += 1
        quote = start + hashes
        triple = source.startswith('"""', quote)
        opening = 3 if triple else 1
        closing = ('"""' if triple else '"') + '#' * hashes
        escape = '\\' + '#' * hashes
        cursor, beginning = quote + opening, quote + opening
        interpolated = False
        while cursor < len(source):
            if source.startswith(escape + '(', cursor):
                interpolated = True
                cursor += len(escape) + 1
                depth = 1
                while cursor < len(source) and depth:
                    end = comment_end(cursor)
                    if end is not None:
                        cursor = end
                    elif source[cursor] == '"' or (source[cursor] == '#' and re.match(r'#+"', source[cursor:])):
                        cursor = read_quoted(cursor)
                    else:
                        if source[cursor] == '(':
                            depth += 1
                        elif source[cursor] == ')':
                            depth -= 1
                        cursor += 1
                continue
            if source.startswith(escape, cursor):
                cursor += len(escape) + 1
                continue
            if source.startswith(closing, cursor):
                raw = source[beginning:cursor]
                if not triple and not interpolated:
                    raw = decode_string(raw) if hashes == 0 else raw
                end = cursor + len(closing)
                result.append(Literal(start, end, raw, source.count('\n', 0, start) + 1, interpolated or triple))
                return end
            cursor += 1
        raise ValueError(f'Unterminated Swift string on line {source.count(chr(10), 0, start) + 1}')
    cursor = 0
    while cursor < len(source):
        end = comment_end(cursor)
        if end is not None:
            cursor = end
        elif source[cursor] == '"' or (source[cursor] == '#' and re.match(r'#+"', source[cursor:])):
            cursor = read_quoted(cursor)
        else:
            cursor += 1
    return sorted(result, key=lambda item: item.start)


def masked_source(source: str, literals: list[Literal]) -> str:
    # The outer string spans also mask quoted strings nested in interpolations.
    chars = list(source)
    for literal in literals:
        for index in range(literal.start, literal.end):
            if chars[index] != '\n':
                chars[index] = ' '
    result = ''.join(chars)
    result = re.sub(r'//[^\n]*|/\*.*?\*/', lambda match: ''.join('\n' if c == '\n' else ' ' for c in match[0]), result, flags=re.S)
    return result


def first_argument_end(masked: str, opening: int) -> int:
    depth = 0
    for index in range(opening + 1, len(masked)):
        char = masked[index]
        if char in '([{':
            depth += 1
        elif char in ')]}':
            if depth == 0:
                return index
            depth -= 1
        elif char == ',' and depth == 0:
            return index
    return len(masked)


def closing_brace(masked: str, opening: int) -> int:
    depth = 1
    for index in range(opening + 1, len(masked)):
        if masked[index] == '{':
            depth += 1
        elif masked[index] == '}':
            depth -= 1
            if depth == 0:
                return index
    return len(masked)


FORMAT = re.compile(r'%(?:(\d+)\$)?([-+ #0]*)(\d+|\*(?:\d+\$)?)?(?:\.(\d+|\*(?:\d+\$)?))?(hh|ll|h|l|L|z|j|t)?([@diuoxXfFeEgGaAcCsSp])')


def placeholders(value: str) -> Counter[tuple[int, str]]:
    signature: Counter[tuple[int, str]] = Counter()
    cursor, next_argument = 0, 1
    while cursor < len(value):
        if value[cursor] != '%':
            cursor += 1
            continue
        if value.startswith('%%', cursor):
            cursor += 2
            continue
        match = FORMAT.match(value, cursor)
        if not match:
            # A literal percent is possible in a SwiftUI LocalizedStringKey.
            cursor += 1
            continue
        position, _, width, precision, length, conversion = match.groups()
        for item in (width, precision):
            if item and item.startswith('*'):
                explicit = item[1:].rstrip('$')
                argument = int(explicit) if explicit else next_argument
                if not explicit:
                    next_argument += 1
                signature[(argument, 'd')] += 1
        argument = int(position) if position else next_argument
        if not position:
            next_argument += 1
        signature[(argument, (length or '') + conversion)] += 1
        cursor = match.end()
    return signature


UI_CALLS = 'Text|Label|Button|TextField|SecureField|TextEditor|Section|Toggle|Picker|DatePicker|DisclosureGroup|ProgressView|LabeledContent|navigationTitle|accessibilityLabel|accessibilityValue|confirmationDialog|alert'


def audit(root: Path) -> dict[str, object]:
    errors: list[str] = []
    interpolation_review: list[str] = []
    catalogs: dict[str, dict[str, str]] = {}
    for language in ('en', 'fr-CA'):
        for table in ('Localizable', 'InfoPlist'):
            path = root / 'Harbour' / f'{language}.lproj' / f'{table}.strings'
            try:
                catalogs[f'{language}/{table}'] = read_catalog(path)
            except (OSError, ValueError) as error:
                errors.append(str(error))
    if len(catalogs) != 4:
        return {'errors': errors, 'interpolation_review': [], 'catalog_keys': 0}
    for table in ('Localizable', 'InfoPlist'):
        english, french = catalogs[f'en/{table}'], catalogs[f'fr-CA/{table}']
        for key in sorted(english.keys() - french.keys()):
            errors.append(f'{table}: missing French key {key!r}')
        for key in sorted(french.keys() - english.keys()):
            errors.append(f'{table}: missing English key {key!r}')
        for key in sorted(english.keys() & french.keys()):
            if not french[key].strip():
                errors.append(f'{table}: blank French translation for {key!r}')
            if table == 'Localizable' and english[key] != key:
                errors.append(f'Localizable: English identity translation changed for {key!r}')
            original = english[key] if table == 'InfoPlist' else key
            if placeholders(original) != placeholders(french[key]):
                errors.append(f'{table}: format argument mismatch for {key!r}: {dict(placeholders(original))} != {dict(placeholders(french[key]))}')
    try:
        info = plistlib.loads((root / 'Harbour' / 'Info.plist').read_bytes())
        expected = {key: value for key, value in info.items() if key.startswith('NS') and key.endswith('UsageDescription')}
        for language in ('en', 'fr-CA'):
            actual = catalogs[f'{language}/InfoPlist']
            for key in sorted(expected.keys() - actual.keys()):
                errors.append(f'InfoPlist: {language} permission missing: {key}')
        for key, value in expected.items():
            if catalogs['en/InfoPlist'].get(key) != value:
                errors.append(f'InfoPlist: English permission differs from Info.plist: {key}')
    except (OSError, ValueError) as error:
        errors.append(str(error))
    available = catalogs['en/Localizable']
    checked_keys: set[str] = set()
    explicit_calls, implicit_calls, bounded_uses = 0, 0, 0
    paths = sorted((root / 'Harbour').glob('*.swift'))
    # Include lower-level packages so a future explicit call there is checked too.
    paths += sorted((root / 'HarbourCore' / 'Sources').rglob('*.swift'))
    paths += sorted((root / 'HarbourRuntime' / 'Sources').rglob('*.swift'))
    for path in paths:
        source = path.read_text()
        try:
            literals = swift_literals(source)
        except ValueError as error:
            errors.append(f'{path.relative_to(root)}: {error}')
            continue
        masked = masked_source(source, literals)
        patterns = [(r'\bL10n\.(?:string|format)\s*\(', True)]
        if path.parent.name == 'Harbour':
            patterns.append((r'\b(?:' + UI_CALLS + r')\s*\(', False))
        for pattern, explicit in patterns:
            for call in re.finditer(pattern, masked):
                opening = call.end() - 1
                end = first_argument_end(masked, opening)
                candidates = [item for item in literals if opening < item.start and item.end <= end]
                # Text(verbatim:) intentionally bypasses LocalizedStringKey lookup.
                if not explicit and re.match(r'\s*verbatim\s*:', masked[opening + 1:end]):
                    continue
                for literal in candidates:
                    where = f'{path.relative_to(root)}:{literal.line}'
                    if literal.interpolated:
                        interpolation_review.append(f'{where}: {source[literal.start:literal.end]}')
                        continue
                    # String fields may be empty, punctuation, units, or numeric examples.
                    if not literal.text or (not explicit and not re.search(r'[A-Za-z]', literal.text)):
                        continue
                    prefix = masked[opening + 1:literal.start]
                    # Nested calls are checked by their own entry, not as UI keys.
                    if '(' in prefix or '[' in prefix:
                        continue
                    # Ignore labelled arguments such as a Button's systemImage.
                    if re.search(r'\w+\s*:\s*$', prefix):
                        continue
                    if explicit:
                        explicit_calls += 1
                    else:
                        implicit_calls += 1
                    checked_keys.add(literal.text)
                    if literal.text not in available:
                        errors.append(f'{where}: missing {"explicit L10n" if explicit else "UI literal"} key {literal.text!r}')
        # These lower-level outputs are translated by the app at display time.
        # Keep their boundaries explicit so prompts, IDs, and parser vocabulary
        # do not accidentally become user-facing catalog requirements.
        ranges: list[tuple[int, int]] = []
        for declaration in re.finditer(r'\bvar\s+errorDescription\s*:\s*String\?\s*\{', masked):
            opening = declaration.end() - 1
            ranges.append((opening, closing_brace(masked, opening)))
        if path.name == 'HealthRules.swift':
            for call in re.finditer(r'\bsummary\s*:\s*(?=")', source):
                candidate = next((item for item in literals if item.start >= call.end()), None)
                if candidate:
                    ranges.append((candidate.start - 1, candidate.end))
            declaration = re.search(r'\bfunc\s+guidance\s*\([^)]*\)[^{]*\{', masked)
            if declaration:
                opening = declaration.end() - 1
                ranges.append((opening, closing_brace(masked, opening)))
        if path.name == 'Evaluation.swift':
            for call in re.finditer(r'\bCheckResult\s*\(', masked):
                opening = call.end() - 1
                ranges.append((opening, first_argument_end(masked, opening)))
            declaration = re.search(r'\blet\s+routingCases\s*:[^=]*=\s*\[', masked)
            if declaration:
                end = masked.find(']', declaration.end())
                ranges.append((declaration.end() - 1, end))
        for literal in literals:
            if literal.interpolated or not literal.text or not any(start < literal.start and literal.end <= end for start, end in ranges):
                continue
            # The dynamic emergency-check prefix has a dedicated format key.
            if path.name == 'Evaluation.swift' and literal.text == 'Emergency sign: ':
                continue
            bounded_uses += 1
            checked_keys.add(literal.text)
            if literal.text not in available:
                errors.append(f'{path.relative_to(root)}:{literal.line}: missing bounded output key {literal.text!r}')
    return {
        'errors': sorted(set(errors)),
        'catalog_keys': len(available),
        'permission_keys': len(catalogs['en/InfoPlist']),
        'explicit_literal_uses': explicit_calls,
        'implicit_ui_literal_uses': implicit_calls,
        'bounded_content_uses': bounded_uses,
        'source_keys_checked': len(checked_keys),
        'interpolation_review': sorted(set(interpolation_review)),
        'limitation': 'Source consistency only. Review dynamic strings, persisted/generated text, SwiftUI interpolation keys, plural grammar, runtime language selection, and rendered screens separately.',
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1], help='iOS project directory')
    parser.add_argument('--json', action='store_true', help='Print machine-readable audit output')
    args = parser.parse_args()
    report = audit(args.root.resolve())
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f'Catalogs: {report["catalog_keys"]} interface keys, {report.get("permission_keys", 0)} permission keys per language.')
        print(f'Source: {report.get("explicit_literal_uses", 0)} explicit literal uses, {report.get("implicit_ui_literal_uses", 0)} implicit UI literal uses, {report.get("bounded_content_uses", 0)} bounded output uses, {report.get("source_keys_checked", 0)} distinct keys checked.')
        for error in report['errors']:
            print('ERROR: ' + error)
        for item in report['interpolation_review']:
            print('REVIEW SWIFTUI KEY: ' + item)
        print(report.get('limitation', 'Catalog parsing failed.'))
        print('PASS' if not report['errors'] else 'FAIL')
    return 1 if report['errors'] else 0


if __name__ == '__main__':
    sys.exit(main())
