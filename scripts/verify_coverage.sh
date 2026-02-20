#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/coverage"
SUMMARY_JSON="$ARTIFACT_DIR/coverage-summary.json"

MIN_LINE_COVERAGE="${MIN_LINE_COVERAGE:-0.40}"
COVERAGE_INCLUDE_PATTERNS="${COVERAGE_INCLUDE_PATTERNS:-Classes/MteRelay/Models/,Classes/MteRelay/Delegates/StreamDelegateProxy.swift,Classes/MteRelay/Helpers/Extensions.swift,Classes/MteRelay/Helpers/RelayHeaderCodec.swift}"

if [ ! -f "$SUMMARY_JSON" ]; then
  echo "Coverage summary not found at $SUMMARY_JSON. Generating coverage first..."
  "$ROOT_DIR/scripts/generate_coverage.sh"
fi

python3 - <<PY
import json
import sys

summary_path = "$SUMMARY_JSON"
min_line_coverage_ratio = float("$MIN_LINE_COVERAGE")
include_patterns = [item.strip() for item in "$COVERAGE_INCLUDE_PATTERNS".split(",") if item.strip()]

with open(summary_path, "r", encoding="utf-8") as file:
    report = json.load(file)

targets = report if isinstance(report, list) else report.get("targets", [])
if not targets:
    print(f"Coverage gate FAILED: unable to parse xccov targets from {summary_path}.")
    sys.exit(1)

target = next((item for item in targets if item.get("name") == "MteRelay"), targets[0])

target_files = target.get("files", [])
if target_files and include_patterns:
    covered_lines = 0
    executable_lines = 0

    for file_item in target_files:
        path = file_item.get("path", "")
        normalized = path.replace("\\\\", "/")
        if "/Tests/" in normalized:
            continue
        if any(pattern in normalized for pattern in include_patterns):
            covered_lines += int(file_item.get("coveredLines", 0))
            executable_lines += int(file_item.get("executableLines", 0))

    if executable_lines > 0:
        line_coverage_ratio = covered_lines / executable_lines
    else:
        line_coverage_ratio = float(target.get("lineCoverage", 0.0))
else:
    line_coverage_ratio = float(target.get("lineCoverage", 0.0))

line_coverage_percent = line_coverage_ratio * 100.0

if line_coverage_ratio + 1e-12 < min_line_coverage_ratio:
    print(f"Coverage gate FAILED: line coverage {line_coverage_ratio:.4f} ({line_coverage_percent:.2f}%) is below threshold {min_line_coverage_ratio:.4f} ({min_line_coverage_ratio*100:.2f}%).")
    sys.exit(1)

print(f"Coverage gate PASSED: line coverage {line_coverage_ratio:.4f} ({line_coverage_percent:.2f}%) meets threshold {min_line_coverage_ratio:.4f} ({min_line_coverage_ratio*100:.2f}%).")
PY
