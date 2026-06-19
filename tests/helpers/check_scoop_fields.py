#!/usr/bin/env python3
"""
Validates structural consistency of the Scoop manifest.
Usage: check_scoop_fields.py <manifest.json> <expected_version>
Exits non-zero and prints an error message on any failure.
"""
import json
import sys

manifest_path, expected_version = sys.argv[1], sys.argv[2]

with open(manifest_path) as f:
    d = json.load(f)

errors = []

if d.get("version") != expected_version:
    errors.append(
        f"version '{d.get('version')}' does not match VERSION file '{expected_version}'"
    )

for field in ("url", "hash", "extract_dir", "env_add_path"):
    if not d.get(field):
        errors.append(f"missing or empty required field: '{field}'")

expected_dir = f"git-review-workflow-{d.get('version', '')}"
if d.get("extract_dir") != expected_dir:
    errors.append(
        f"extract_dir '{d.get('extract_dir')}' should be '{expected_dir}' "
        f"(git-review-workflow-<version>)"
    )

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
