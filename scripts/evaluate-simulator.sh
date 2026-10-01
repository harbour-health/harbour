#!/bin/bash
set -euo pipefail
device="${1:?Usage: evaluate-simulator.sh SIMULATOR_UUID [OUTPUT_DIRECTORY]}"
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${2:-$root/docs/results/care-tools}"
bundle="com.matteopolak.harbour"
container="$(xcrun simctl get_app_container "$device" "$bundle" data)"
mkdir -p "$output"
for model in small balanced; do
    report="$container/Library/Application Support/Harbour/model-evaluation-$model.json"
    # Only delete this generated evaluation artifact; never the records archive.
    rm -f "$report"
    args=(--evaluate-model --evaluate-all-efforts)
    if [[ "$model" == balanced ]]; then args+=(--evaluate-balanced); fi
    xcrun simctl launch --terminate-running-process "$device" "$bundle" "${args[@]}"
    echo "Evaluating $model: 19 fictional prompts at each of three effort settings."
    previous_count=-1
    finished=no
    for ((attempt=0; attempt<900; attempt++)); do
        if [[ -f "$report" ]]; then
            progress="$(python3 - "$report" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
print(len(report['runs']), 'yes' if report.get('complete', False) else 'no')
PY
)"
            read -r count finished <<< "$progress"
            if [[ "$count" != "$previous_count" ]]; then echo "$model: $count/57 cases completed"; previous_count="$count"; fi
            if [[ "$finished" == yes ]]; then break; fi
        fi
        sleep 2
    done
    [[ "$finished" == yes ]] || { echo "Evaluation did not finish within 30 minutes; any partial report remains in the app container."; exit 1; }
    cp "$report" "$output/$model.json"
    python3 - "$output/$model.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
runs = report['runs']
print(f"{sum(item['passed'] for item in runs)}/{len(runs)} cases passed")
for item in runs:
    if not item['passed']: print(item['effort'], item['input'], '=>', item['observed'])
PY
done
echo "Evaluation reports saved to $output"
