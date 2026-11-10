#!/usr/bin/env bash
# Fails when line coverage of Sources/CaptureCore is below the given percent.
# Run after: swift test --enable-code-coverage
# Usage: scripts/check-coverage.sh 90
set -euo pipefail

minimum="${1:-90}"
cd "$(dirname "$0")/.."

report="$(swift test --enable-code-coverage --show-codecov-path)"

python3 -I - "$report" "$minimum" <<'PY'
import json, sys

report_path, minimum = sys.argv[1], float(sys.argv[2])
with open(report_path) as f:
    data = json.load(f)

covered = total = 0
for entry in data["data"]:
    for file in entry["files"]:
        if "/Sources/CaptureCore/" in file["filename"]:
            lines = file["summary"]["lines"]
            covered += lines["covered"]
            total += lines["count"]
            print(f'{file["filename"].split("/Sources/")[1]}: {lines["percent"]:.1f}%')

if total == 0:
    sys.exit("No coverage found for Sources/CaptureCore.")
percent = 100.0 * covered / total
print(f"CaptureCore line coverage: {percent:.1f}% (minimum {minimum:.0f}%)")
if percent < minimum:
    sys.exit(1)
PY
