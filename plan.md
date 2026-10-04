# Plan: DVWA + Org SAST Pipeline

Scope: vendor DVWA into this repo as SAST test content, then add a reusable
SAST workflow (CodeQL + Semgrep) and call it from this repo's CI.

## Decisions

- DVWA lives in subdirectory `dvwa/` (Node app/contract stays at root)
- DVWA's `.github/` is stripped (excludes `vulnerable.yml` secret-leak demo,
  `docker-image.yml`, and the rest of its workflows)
- SAST engine: **both CodeQL and Semgrep**
- SAST job runs in the **caller repo only** (reusable repo has no self-CI by design)
- Hard rule: DVWA is cloned and copied as files only — no docker, no apache/php
  install, no DVWA scripts, nothing executed. SAST is static analysis only.

## Workflow rules (org policy)

- All work on `dev`, tested on `dev`, then PR `dev` → `main` (no feature branches)
- SSH-signed commits required
- SHA-pin all actions with `# vX.Y.Z` comments
- Single rolling release tag `v1.0.0` on the reusable repo (re-cut after
  merging → repin caller)
- Dependabot (github-actions, weekly Mon, `ci` prefix) configured in both repos

## Phase 0 — housekeeping (both repos)

`dev` is behind `main` in both repos after local merges. Fast-forward
`dev` → `main` on each, push, so all new work starts current.

## Phase 1 — clone DVWA (read-only)

```
git clone https://github.com/digininja/DVWA.git ~/Projects/DVWA
```

- Default branch `master`, HEAD `43b0f8b`, GPL-3.0, ~252 files / 169 PHP, 3MB
- Untouched copy; nothing installed or run
- Intentionally vulnerable (upstream SECURITY.md: do not report the vulns);
  never deploy internet-facing

## Phase 2 — vendor into caller-repo (`dev`)

- `rsync -a --exclude .git --exclude .github/ ~/Projects/DVWA/ dvwa/`
  - ~252 files; keeps `COPYING.txt` (GPL requires it)
  - drops all 5 of DVWA's workflows
- Caller `README.md`: add "Vendored third-party code" note — `dvwa/` is
  unmodified GPL-3.0 DVWA from `digininja/DVWA` for SAST test content;
  the repo's own code stays MIT
- Verify root package contract untouched:
  `npm ci && npm run build && npm run test:ci` green
- Signed commit → push `dev` → **pause for review**

## Phase 3 — reusable repo: new `sast.yml` (`dev`)

New `.github/workflows/sast.yml` with `workflow_call`, matching
`build-test.yml` conventions (ubuntu-24.04, `contents: read`, SHA-pinned
actions with `# vX.Y.Z` comments).

Resolved pins:

| Action | SHA | Tag |
|---|---|---|
| `actions/checkout` | `3d3c42e5aac5ba805825da76410c181273ba90b1` | v7.0.1 |
| `github/codeql-action/{init,analyze,upload-sarif}` | `2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2` | v4.38.2 |
| Semgrep | `semgrep==1.179.0` (pip pin) | released 2026-10-02 |

Inputs (minimal, matching the build contract style):

- `languages` (default `'php,javascript'`)
- `semgrep-config` (default `'auto'`)

Jobs:

1. **CodeQL**: `codeql-action/init` → `codeql-action/analyze`;
   `permissions: contents: read, security-events: write`.
   Report-only (uploads alerts, does not fail on findings)
2. **Semgrep**: version-pinned pip install →
   `semgrep scan --config <input> --sarif` → `codeql-action/upload-sarif`.
   **No `--error` flag → report-only.** DVWA is designed to always produce
   findings; a blocking SAST would make every future PR unmergeable.
   A fail-threshold input can be added later if wanted.

Push `dev`. Tested via a caller PR (Phase 4) — no self-CI on the reusable repo.

## Phase 4 — caller calls SAST (`dev`, same PR as Phase 2)

Add a second job to `.github/workflows/ci.yml`:

```yaml
  sast:
    permissions:
      contents: read
      security-events: write        # required for SARIF upload
    uses: enofei/reusable-build-test/.github/workflows/sast.yml@<SHA-X>  # provisional
    with:
      languages: 'php,javascript'
```

- `SHA-X` = the exact Phase-3 commit (immutable, testable before any tag moves)
- Job-level `permissions` override the workflow-level `contents: read`
- Open PR `dev` → `main`; expect:
  - `build-and-test` green (Phase 2 broke nothing)
  - `sast` runs CodeQL + Semgrep over `dvwa/` → dozens+ alerts in
    Security → Code scanning (positive control)
- Verify via `gh pr checks` + `gh api repos/.../code-scanning/alerts`

## Phase 5 — release & repin

1. Reusable: PR `dev` → `main`, merge (GitHub-signed)
2. Re-cut `v1.0.0` → new main head; confirm with
   `scripts/resolve-action-sha.sh`
3. Caller: update **both** pins (`build-test.yml` + `sast.yml`) to the tag
   SHA `# v1.0.0`, push to the same open PR, re-check CI
4. Merge caller PR → `main`
5. Tidy: only `dev`/`main` remain on both repos (branch rule)

## Risks / notes

| Risk | Mitigation |
|---|---|
| SAST blocks all future PRs (DVWA always dirty) | Report-only by design (Phase 3); flip later via input |
| SARIF upload needs permissions | Job-level `security-events: write` on the calling job |
| GPL-3.0 code in an MIT repo | `COPYING.txt` kept + README attribution; dual-license noted |
| First CodeQL run slow (~2–5 min) | One-time DB build; subsequent runs cached |
| Semgrep `--config auto` needs registry egress | Available on GH-hosted runners |
| DVWA workflows executing in this repo | Stripped in Phase 2 — never uploaded |

## Phases 6–8 — OPA policy gate (executed)

Reusable repo (`dev`):

- `sast.yml` hardened: Semgrep runs in digest-pinned container
  `semgrep/semgrep:1.179.0@sha256:93963d9295a366f59e4850127b1550400ee7b388f04fe144e4a1f6325d96e01b`
  (no pip), `semgrep scan` invoked explicitly (image has no ENTRYPOINT),
  `--no-rewrite-rule-ids`, scans vendored rules (default input
  `policy/semgrep-rules`), uploads `semgrep-sarif` artifact
  (`if: always()`, `if-no-files-found: error`, retention 1 day)
- New `policy.yml` (`workflow_call`): **main is clamped to
  `enforce-critical`** regardless of caller input; downloads + validates
  SARIF (structure, tool, results, rule table) fail-closed; installs
  conftest `0.71.0` verified against embedded SHA-256
  `765dfefdf0730693d7541ea0147e10d530a54ed257bbfec055ff34c837ffdf72`;
  runs `conftest verify` + `conftest test --parser json --output github`

Caller repo (`dev`):

- `policy/sast.rego` — modes `warn` / `enforce-critical` / `enforce-full`;
  `dvwa/**` never denied (visible as warnings); severity from SARIF
  `result.level` else rule `defaultConfiguration.level` else `warning`;
  malformed input / unknown mode → deny (fail-closed). 10 unit tests.
- `policy/semgrep-rules/` — frozen `https://semgrep.dev/c/auto` bundle
  (1073 rules; sentinel edit documented in `SOURCE.txt`)
- `.github/dependabot.yml` — `cooldown: default-days: 7` (clears the only
  first-party finding)
- `ci.yml` — third job `policy` (`name: Policy`, `if: always()`,
  `needs: [sast]`) calling `policy.yml`; pull_request-only trigger
  (push trigger used for Phase 8, removed after: same-SHA duplicate
  `Policy / Gate` checks could race a green dev-push against a red PR gate)

Phase 8 evidence (each on real CI, recorded in `progress.md`):

| Test | Result |
|---|---|
| baseline `enforce-critical`, dev + PR | green; 71 dvwa findings warn-only |
| probe `eval($_GET…)` at root, `mode: warn` on dev | green, `##[warning][warn] … gate-probe.php` |
| same commit, PR to main | **red**, clamped → `##[error][enforce-critical] … gate-probe.php` |
| `mode: enforce-critical` explicit, probe present | red (error denied), first-party warning advisory |
| `mode: enforce-full`, cooldown removed | red: `##[error][enforce-full] … dependabot … (warning)` |
| same commit PR to main (clamped) | green (warning advisory under critical) |

Check names confirmed live: `Build & Test / Build & Test`,
`SAST / Semgrep`, `Policy / Gate`.

## Phase 5 — release, repin, enforcement (order fixed by evidence)

1. Reusable: PR `dev` → `main`, merge (GitHub-signed)
2. Re-cut rolling `v1.0.0` → new main head
3. Caller: repin **all three** (`build-test.yml`, `sast.yml`,
   `policy.yml`) to tag SHA `# v1.0.0`; commit break-glass runbook (this
   file) + README CI docs; PR re-checks green → merge PR #9 → `main`
4. Enable required checks via **granular endpoint only**:
   `POST …/branches/main/protection/required_status_checks` with
   `strict: true`, contexts `["Policy / Gate", "SAST / Semgrep"]`
   (never a full PUT — it would clobber `enforce_admins` etc.)
5. Verify-diff: GET protection before/after; assert `enforce_admins:
   true`, `required_signatures: true`, all `allow_*` unchanged; only
   status checks added → rollback (DELETE endpoint) if anything else moved
6. Direct-push test: fresh unchecked commit `git push origin dev:main`
   → expect GH006 rejection; record actual outcome here
7. Negative test: PR with a first-party error finding → `Policy / Gate`
   red → merge blocked → revert
8. `Semgrep OSS` (code-scanning PR decoration) shows dvwa alerts —
   advisory, deliberately **not** required

### Break-glass runbook (required status checks on main)

With `enforce_admins: true` + required checks, a gate outage blocks all
merges; the UI cannot bypass. Recovery:

```bash
# 1. remove the status-check requirement (signatures stay intact)
gh api -X DELETE repos/enofei/caller-repo/branches/main/protection/required_status_checks
# 2. fix the problem, merge with signatures still enforced
# 3. re-add and verify
gh api -X POST repos/enofei/caller-repo/branches/main/protection/required_status_checks \
  -f strict=true -F contexts[]="Policy / Gate" -F contexts[]="SAST / Semgrep"
gh api repos/enofei/caller-repo/branches/main/protection \
  --jq '{enforce_admins: .enforce_admins.enabled, signatures: .required_signatures, checks: .required_status_checks.contexts, allow_force: .allow_force_pushes.enabled}'
```

Do not remove `required_signatures` to solve a gate problem — the
runbook only ever touches `required_status_checks`.

## Execution status

- [x] Plan finalized, pins resolved
- [x] Phase 0 — fast-forward `dev` on both repos
- [x] Phase 1 — clone DVWA
- [x] Phase 2 — vendor into `dvwa/`
- [x] Phase 3 — `sast.yml` in reusable repo (Semgrep-only; CodeQL dropped — no PHP)
- [x] Phase 4 — caller SAST job + PR #9
- [x] Phases 6–8 — OPA gate (reusable `policy.yml`, caller Rego + rules, matrix green)
- [ ] Phase 5 — merge reusable, tag re-cut, repin, merge PR #9, required checks, tests
