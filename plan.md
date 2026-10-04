# Plan: DVWA + Org SAST Pipeline

Scope: vendor DVWA into this repo as SAST test content, then add a reusable
SAST workflow (CodeQL + Semgrep) and call it from this repo's CI.

## Decisions

- DVWA lives in subdirectory `dvwa/` (Node app/contract stays at root)
- DVWA's `.github/` is stripped (excludes `vulnerable.yml` secret-leak demo,
  `docker-image.yml`, and the rest of its workflows)
- SAST engine: **both CodeQL and Semgrep**
- SAST job runs in the **caller repo only** (reusable repo has no self-CI by design)
- Hard rule: DVWA is cloned and copied as files only, no docker, no apache/php
  install, no DVWA scripts, nothing executed. SAST is static analysis only.

## Workflow rules (org policy)

- All work on `dev`, tested on `dev`, then PR `dev` → `main` (no feature branches)
- SSH-signed commits required
- SHA-pin all actions with `# vX.Y.Z` comments
- Single rolling release tag `v1.0.0` on the reusable repo (re-cut after
  merging → repin caller)
- Dependabot (github-actions, weekly Mon, `ci` prefix) configured in both repos

## Phase 0: housekeeping (both repos)

`dev` is behind `main` in both repos after local merges. Fast-forward
`dev` → `main` on each, push, so all new work starts current.

## Phase 1: clone DVWA (read-only)

```
git clone https://github.com/digininja/DVWA.git ~/Projects/DVWA
```

- Default branch `master`, HEAD `43b0f8b`, GPL-3.0, ~252 files / 169 PHP, 3MB
- Untouched copy; nothing installed or run
- Intentionally vulnerable (upstream SECURITY.md: do not report the vulns);
  never deploy internet-facing

## Phase 2: vendor into caller-repo (`dev`)

- `rsync -a --exclude .git --exclude .github/ ~/Projects/DVWA/ dvwa/`
  - ~252 files; keeps `COPYING.txt` (GPL requires it)
  - drops all 5 of DVWA's workflows
- Caller `README.md`: add "Vendored third-party code" note: `dvwa/` is
  unmodified GPL-3.0 DVWA from `digininja/DVWA` for SAST test content;
  the repo's own code stays MIT
- Verify root package contract untouched:
  `npm ci && npm run build && npm run test:ci` green
- Signed commit → push `dev` → **pause for review**

## Phase 3: reusable repo: new `sast.yml` (`dev`)

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

Push `dev`. Tested via a caller PR (Phase 4); the reusable repo has no self-CI.

## Phase 4: caller calls SAST (`dev`, same PR as Phase 2)

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

## Phase 5: release & repin

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
| DVWA workflows executing in this repo | Stripped in Phase 2, never uploaded |

## Phases 6–8: OPA policy gate (executed)

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

- `policy/sast.rego`: modes `warn` / `enforce-critical` / `enforce-full`;
  `dvwa/**` never denied (visible as warnings); severity from SARIF
  `result.level` else rule `defaultConfiguration.level` else `warning`;
  malformed input / unknown mode → deny (fail-closed). 10 unit tests.
- `policy/semgrep-rules/`: frozen `https://semgrep.dev/c/auto` bundle
  (1073 rules; sentinel edit documented in `SOURCE.txt`)
- `.github/dependabot.yml`: `cooldown: default-days: 7` (clears the only
  first-party finding)
- `ci.yml`: third job `policy` (`name: Policy`, `if: always()`,
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

## Phase 5: release, repin, enforcement (executed)

1. [x] Reusable: PR #4 `dev` → `main` merged → `4584e68`
2. [x] Re-cut rolling `v1.0.0` → `4584e68` (verified via `resolve-action-sha.sh`)
3. [x] Caller: repinned all three jobs to `4584e68 # v1.0.0`; PR #9 green → merged → `a722418`
4. [x] Required checks enabled. There is **no create sub-endpoint** for
   status checks (`POST`/`PUT` on the sub-resource both 404 while
   disabled; docs only offer `GET`/`PATCH`/`DELETE`), so enabling used
   the full `PUT /branches/main/protection` with a body mirroring the
   GET snapshot exactly plus one added key, then verify-diff:
   - `required_status_checks` added: `strict: true`, contexts
     `Policy / Gate` + `SAST / Semgrep` (auto-bound to app 15368,
     GitHub Actions)
   - every other field byte-identical: `enforce_admins: true`,
     `required_signatures: true`, `allow_force_pushes/deletions:
     false`, `lock_branch/…: false`, reviews/restrictions still absent
5. [x] Direct-push test: fresh signed, never-checked commit
   `git push origin HEAD:main` → **rejected `GH006 … 2 of 2 required
   status checks are expected`** (signature was valid; the rejection was
   purely the gate). Untested-sha direct pushes to `main` are closed.
6. [x] Negative test (PR #10, `eval($_GET…)` at repo root):
   `Policy / Gate` **fail**, run exit 1, `mergeStateStatus: BLOCKED`,
   `gh pr merge` refused: "the base branch policy prohibits the merge".
   Probe reverted; `git diff origin/main origin/dev` empty.
7. [x] `Semgrep OSS` (code-scanning PR decoration) reports dvwa alerts
   (advisory, deliberately **not** required)

### Break-glass runbook (required status checks on main)

With `enforce_admins: true` + required checks, a gate outage blocks all
merges; the UI cannot bypass (`--admin` is refused too). Recovery:

```bash
# 1. remove ONLY the status-check requirement (signatures stay intact)
gh api -X DELETE repos/enofei/caller-repo/branches/main/protection/required_status_checks

# 2. fix the problem; merges reopen (signature requirement remains)

# 3. re-enable: no create sub-endpoint exists: full PUT, mirroring a
#    fresh GET snapshot exactly + the one added key, then verify-diff
gh api repos/enofei/caller-repo/branches/main/protection > /tmp/before.json
#    build PUT body from before.json (all enable-flags verbatim) with
#    "required_status_checks": {"strict": true,
#      "contexts": ["Policy / Gate", "SAST / Semgrep"]}
gh api -X PUT repos/enofei/caller-repo/branches/main/protection --input /tmp/body.json
gh api repos/enofei/caller-repo/branches/main/protection \
  --jq '{admins: .enforce_admins.enabled, sigs: .required_signatures.enabled, checks: .required_status_checks.contexts, force: .allow_force_pushes.enabled}'
```

Never touch `required_signatures` to solve a gate problem: only
`required_status_checks` is ever added or removed.

## Execution status

- [x] Plan finalized, pins resolved
- [x] Phase 0: fast-forward `dev` on both repos
- [x] Phase 1: clone DVWA
- [x] Phase 2: vendor into `dvwa/`
- [x] Phase 3: `sast.yml` in reusable repo (Semgrep-only; CodeQL dropped for lack of PHP)
- [x] Phase 4: caller SAST job + PR #9
- [x] Phases 6–8: OPA gate (reusable `policy.yml`, caller Rego + rules, matrix green)
- [x] Phase 5: merge reusable, tag re-cut, repin, merge PR #9, required checks, direct-push + negative tests
