"""Bind scored JSONL evidence to complete evaluator metadata and pinned assets."""
import hashlib
import json
import re
import runpy
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MODEL_PINS = runpy.run_path(str(ROOT / 'scripts/cache-eval-models.py'))['MODELS']
RUNTIME_PINS = runpy.run_path(str(ROOT / 'scripts/prepare-linux-runtime.py'))
QUALITY_KINDS = {'routing', 'prose', 'title', 'visit'}
IDENTITY_FIELDS = ['suiteSHA256', 'executableSHA256', 'sourceSHA256', 'runtimeFilesSHA256',
                   'swiftVersion', 'platform', 'processor', 'logicalProcessors']
INFERENCE_FIELDS = ['context', 'batch', 'threads', 'backend', 'sampling', 'JSONStopping',
                    'efforts', 'repeats', 'repeatScope', 'tokenBudgets', 'grammarPolicy', 'baselinePrompts']
PAIRED_FIELDS = ['suiteSHA256', 'runtimeFilesSHA256', 'swiftVersion', 'platform', 'processor', 'logicalProcessors', 'models']
PAIRED_SETTINGS = [field for field in INFERENCE_FIELDS if field not in {'repeats', 'grammarPolicy', 'baselinePrompts'}]


def sha(data):
    return hashlib.sha256(data.encode('utf-8') if isinstance(data, str) else data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError('Run provenance: ' + message)


def valid_sha(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None


def read_bounded(path, limit):
    require(path.is_file() and path.stat().st_size <= limit, f'missing or oversized evidence: {path}')
    return path.read_bytes()


def key(row):
    return row['caseID'], row.get('effort', 'standard'), row.get('repeatIndex', 0)


def hash_index(items):
    require(isinstance(items, list), 'missing prompt/grammar hash list')
    index = {key(item): item for item in items}
    require(len(index) == len(items), 'duplicate prompt/grammar metadata key')
    return index


def identity(metadata, suite_sha):
    require(metadata.get('complete') is True, 'metadata is incomplete')
    require(metadata.get('suiteSHA256') == suite_sha, 'fixture hash mismatch')
    require(all(field in metadata for field in IDENTITY_FIELDS), 'missing execution identity fields')
    require(isinstance(metadata['logicalProcessors'], int) and metadata['logicalProcessors'] > 0 and metadata['swiftVersion'] and metadata['platform'], 'missing compiler/host identity')
    require(valid_sha(metadata['executableSHA256']), 'missing executable digest')
    for field in ['sourceSHA256', 'runtimeFilesSHA256']:
        require(isinstance(metadata[field], dict) and metadata[field] and all(valid_sha(v) for v in metadata[field].values()), f'invalid {field}')
    runtime = metadata.get('runtime', {})
    require(runtime.get('runtimeBuild') == RUNTIME_PINS['BUILD'] and runtime.get('sourceSHA256') == RUNTIME_PINS['SOURCE_SHA256'] and runtime.get('sourceURL') == RUNTIME_PINS['SOURCE_URL'], 'runtime source pin mismatch')
    require(valid_sha(runtime.get('librarySHA256')) and metadata['runtimeFilesSHA256'].get('lib/libllama.so') == runtime['librarySHA256'], 'runtime library digest mismatch')
    require(isinstance(runtime.get('installedFilesSHA256'), dict) and runtime['installedFilesSHA256'] and all(metadata['runtimeFilesSHA256'].get(k) == v for k, v in runtime['installedFilesSHA256'].items()), 'installed runtime files mismatch')
    specs = metadata.get('models', [])
    require(isinstance(specs, list) and specs and len({s.get('model') for s in specs}) == len(specs), 'missing or duplicate model identities')
    for spec in specs:
        require(spec.get('model') in MODEL_PINS, 'unknown model identity')
        repo, revision, filename, size, digest = MODEL_PINS[spec['model']]
        expected = dict(repository=repo, revision=revision, filename=filename, bytes=size, sha256=digest,
                        url=f'https://huggingface.co/{repo}/resolve/{revision}/{filename}', verified=True)
        require(all(spec.get(k) == v for k, v in expected.items()), 'model asset pin mismatch: ' + spec['model'])
    settings = metadata.get('settings', {})
    require(all(field in settings for field in INFERENCE_FIELDS), 'missing inference settings')
    require(settings['context'] == 4096 and settings['batch'] == 512 and settings['backend'] == 'Linux CPU', 'unexpected inference context/backend')
    require(isinstance(settings['efforts'], str) and set(settings['efforts'].split(',')) <= {'quick', 'standard', 'extended'} and settings['efforts'], 'invalid effort settings')
    require(isinstance(settings['repeats'], int) and 1 <= settings['repeats'] <= 5, 'invalid repetition settings')
    require(isinstance(settings.get('baselinePrompts'), bool) and settings.get('split') in {'all', 'dev', 'heldout'}, 'invalid baseline/split settings')
    result = {field: metadata[field] for field in IDENTITY_FIELDS}
    result['models'] = sorted(specs, key=lambda s: s['model'])
    result['inferenceSettings'] = {field: settings[field] for field in INFERENCE_FIELDS}
    return result


def verify_run_manifest(path, row_paths, suite_sha):
    if path is None:
        return dict(status='missing', reason='No run manifest supplied')
    path = Path(path).resolve()
    manifest_bytes = read_bounded(path, 2_000_000)
    manifest = json.loads(manifest_bytes.decode('utf-8-sig'))
    entries = manifest.get('streams')
    if entries is None:  # Original collection format remains supported.
        entries = [dict(rows=s['path'], rowsSHA256=s['sha256'], metadata=r['metadata'], metadataSHA256=r['metadataSHA256'])
                   for r in manifest.get('runs', []) for s in r.get('streams', [])]
    require(isinstance(entries, list) and 1 <= len(entries) <= 32, 'expected 1...32 stream bindings')
    resolve = lambda value: (path.parent / value).resolve()
    streams = [resolve(e['rows']) for e in entries]
    require(len(set(streams)) == len(streams) and set(streams) == {Path(p).resolve() for p in row_paths}, 'manifest must bind exactly the scored streams, once each')
    metadata_cache, common, evidence = {}, None, []
    for entry, stream in zip(entries, streams):
        data = read_bounded(stream, 64_000_000)
        require(valid_sha(entry.get('rowsSHA256')) and sha(data) == entry['rowsSHA256'], f'stream hash mismatch: {stream.name}')
        metadata_path = resolve(entry['metadata'])
        metadata_bytes = read_bounded(metadata_path, 4_000_000)
        require(valid_sha(entry.get('metadataSHA256')) and sha(metadata_bytes) == entry['metadataSHA256'], 'metadata hash mismatch')
        metadata = metadata_cache.setdefault(metadata_path, json.loads(metadata_bytes.decode('utf-8-sig')))
        current = identity(metadata, suite_sha)
        require(common is None or current == common, 'mixed source/executable/runtime/models/inference settings across collected runs')
        common = current
        rows = [json.loads(line) for line in data.decode('utf-8-sig').splitlines() if line.strip()]
        require(rows and len({r.get('model') for r in rows}) == 1, 'stream must contain exactly one model')
        model = rows[0]['model']
        require(model in {s['model'] for s in metadata['models']}, 'stream model absent from metadata')
        prompts = hash_index(metadata.get('promptSHA256', {}).get(model))
        grammars = hash_index(metadata.get('responseGrammarSHA256', {}).get(model))
        seen = set()
        for row in rows:
            k = key(row)
            require(k not in seen, 'duplicate row key within stream')
            seen.add(k)
            require(row.get('baselinePrompts') == metadata['settings']['baselinePrompts'], 'row baseline flag mismatch')
            if row.get('kind') in QUALITY_KINDS:
                require(metadata['settings']['split'] == 'all' or row.get('split') == metadata['settings']['split'], 'row split mismatch')
                require(row.get('context') == metadata['settings']['context'] and row.get('batch') == metadata['settings']['batch'], 'row context/batch mismatch')
                require(row.get('effort') in metadata['settings']['efforts'].split(','), 'row effort absent from declared settings')
                require(isinstance(row.get('repeatIndex'), int) and 0 <= row['repeatIndex'] < metadata['settings']['repeats'], 'row repetition outside declared settings')
                require(isinstance(row.get('prompt'), str) and row['prompt'], 'prepared quality prompt missing')
            if row.get('prompt'):
                expected = dict(caseID=k[0], effort=k[1], repeatIndex=k[2], prompt=sha(row['prompt']), replyPrompt=sha(row['replyPrompt']) if row.get('replyPrompt') else None)
                require(prompts.get(k) == expected, 'prepared prompt hash mismatch')
            require(grammars.get(k) == dict(caseID=k[0], effort=k[1], repeatIndex=k[2], sha256=sha(row['responseGrammar']) if row.get('responseGrammar') else None), 'response grammar hash mismatch')
        require(set(prompts) == {key(r) for r in rows if r.get('prompt')} and set(grammars) == seen, 'metadata hash coverage mismatch')
        if model in metadata.get('resultSHA256', {}):
            require(metadata['resultSHA256'][model] == entry['rowsSHA256'], 'metadata result hash mismatch')
        evidence.append(dict(rows=entry['rows'], rowsSHA256=entry['rowsSHA256'], metadata=entry['metadata'], metadataSHA256=entry['metadataSHA256'], model=model, totalRows=len(rows)))
    if 'identity' in manifest:
        require(manifest['identity'] == common, 'collection identity disagrees with verified metadata')
    return dict(status='verified', manifestSHA256=sha(manifest_bytes), identity=common, streams=evidence,
                meaning='Hashes bind recorded evidence and declared pinned assets; they are not cryptographic attestation of the execution host.')


def paired_identity_matches(before, after):
    return (all(before.get(field) == after.get(field) for field in PAIRED_FIELDS) and
            all(before.get('inferenceSettings', {}).get(field) == after.get('inferenceSettings', {}).get(field) for field in PAIRED_SETTINGS))
