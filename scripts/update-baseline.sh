#!/usr/bin/env bash
# Regenerates policy/baseline.json: re-runs the three scanners locally
# (digest-pinned images) -> SARIF -> scripts/sarif_to_baseline.py.
# Only vendored paths (dvwa/) are baselined; first-party findings must be
# fixed, never baselined. Requires docker, network, policy/semgrep-rules.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.baseline-scan"
SEMGREP_IMAGE='semgrep/semgrep:1.179.0@sha256:93963d9295a366f59e4850127b1550400ee7b388f04fe144e4a1f6325d96e01b'
GITLEAKS_IMAGE='ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f'
TRIVY_IMAGE='ghcr.io/aquasecurity/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa'

mkdir -p "$WORK"
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

run_in() {
  local image="$1"
  shift
  docker run --rm -v "$ROOT:/repo" -w /repo "$image" "$@"
}

echo "==> semgrep"
run_in "$SEMGREP_IMAGE" \
  semgrep scan --config policy/semgrep-rules --no-rewrite-rule-ids \
  --sarif --output /repo/.baseline-scan/semgrep.sarif .

echo "==> gitleaks (dir)"
run_in "$GITLEAKS_IMAGE" \
  dir . --redact --no-banner --exit-code 0 \
  --report-format sarif --report-path /repo/.baseline-scan/gitleaks-dir.sarif

echo "==> gitleaks (git)"
run_in "$GITLEAKS_IMAGE" \
  git . --redact --no-banner --exit-code 0 \
  --report-format sarif --report-path /repo/.baseline-scan/gitleaks-git.sarif

echo "==> trivy fs"
run_in "$TRIVY_IMAGE" \
  fs --scanners vuln,misconfig --format sarif \
  --output /repo/.baseline-scan/trivy.sarif \
  --exit-code 0 --skip-check-update --skip-version-check .

# Container writes are root-owned; hand them back to the caller.
chown "$(id -u):$(id -g)" "$WORK"/*.sarif 2>/dev/null || true

python3 "$ROOT/scripts/sarif_to_baseline.py" \
  --path dvwa/ \
  -o "$ROOT/policy/baseline.json" \
  "$WORK"/semgrep.sarif "$WORK"/gitleaks-dir.sarif \
  "$WORK"/gitleaks-git.sarif "$WORK"/trivy.sarif

echo "==> policy/baseline.json regenerated; review the diff before committing"
