#!/usr/bin/env python3
"""Fold SARIF reports into a findings baseline (policy/baseline.json).

Each finding's fingerprint is sha256("tool|ruleId|path|message") where tool is
the SARIF run's tool.driver.name. The gate recomputes the same fingerprint and
suppresses findings whose hash is listed in the baseline. Entries are kept only
for paths under one of the --path prefixes (the baseline is for vendored
content; first-party findings must be fixed, not baselined).

Usage:
    sarif_to_baseline.py --path dvwa/ -o policy/baseline.json scan1.sarif scan2.sarif
"""

import argparse
import glob
import hashlib
import json
import sys


def iter_findings(paths):
    for path in paths:
        with open(path) as f:
            doc = json.load(f)
        for run in doc.get("runs", []):
            tool = str(((run.get("tool") or {}).get("driver") or {}).get("name", ""))
            if not tool:
                sys.exit(f"{path}: run missing tool.driver.name")
            for result in run.get("results", []):
                locations = result.get("locations") or [{}]
                uri = (
                    (locations[0].get("physicalLocation") or {})
                    .get("artifactLocation", {})
                    .get("uri", "<unknown-path>")
                )
                message = ((result.get("message") or {}).get("text")) or "<no message>"
                rule_id = result.get("ruleId", "<unknown-rule>")
                yield tool, rule_id, uri, message


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sarif", nargs="+", help="SARIF files to read")
    parser.add_argument(
        "--path",
        action="append",
        dest="paths",
        default=[],
        help="keep findings whose path starts with this prefix (repeatable)",
    )
    parser.add_argument("-o", "--output", required=True, help="baseline JSON to write")
    args = parser.parse_args()

    files = sorted({f for pattern in args.sarif for f in glob.glob(pattern)})
    if not files:
        sys.exit("no SARIF files matched")

    seen = {}
    for tool, rule_id, uri, message in iter_findings(files):
        if args.paths and not any(uri.startswith(p) for p in args.paths):
            continue
        sha = hashlib.sha256(f"{tool}|{rule_id}|{uri}|{message}".encode("utf-8")).hexdigest()
        seen[sha] = {
            "sha256": sha,
            "tool": tool,
            "ruleId": rule_id,
            "path": uri,
            "message": message,
        }

    entries = sorted(seen.values(), key=lambda e: (e["tool"], e["path"], e["ruleId"], e["message"]))
    with open(args.output, "w") as f:
        json.dump({"fingerprints": entries}, f, indent=2, sort_keys=False)
        f.write("\n")
    print(f"wrote {len(entries)} fingerprints to {args.output}")


if __name__ == "__main__":
    main()
