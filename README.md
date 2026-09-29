# caller-repo

A sample Node.js application that exercises the organization's shared CI pipeline:

**[`enofei/reusable-build-test`](https://github.com/enofei/reusable-build-test)** → `.github/workflows/build-test.yml`

## How CI works

[`ci.yml`](.github/workflows/ci.yml) contains a single job that *calls* the org reusable workflow instead of defining build steps locally:

```yaml
jobs:
  build-and-test:
    uses: enofei/reusable-build-test/.github/workflows/build-test.yml@5c82f30a632c051641a32c651017fbf7d39ccfe6  # v1.1.0
    with:
      node-version: '24'
      test-command: 'npm run test:ci'
      security-checks: true
```

The reusable workflow then runs, on every pull request to `main` / `develop`:

1. `npm ci` — install from `package-lock.json`
2. `npm run build` — bundle `src/` into `dist/`
3. `npm run test:ci` — Node's built-in test runner
4. `npm audit --audit-level=high` — security audit (`security-checks: true`)

Node.js **24** (current Active LTS) is used consistently across the reusable workflow's default, this repository's `ci.yml`, and the `engines` field in `package.json`.

## Contract with the reusable workflow

The reusable workflow assumes this repository provides:

- `package.json` **and** `package-lock.json` (npm caching fails without the lockfile)
- a `build` script
- the script named in `test-command` (`test:ci`)

## Local development

```bash
npm ci              # install dependencies
npm run build       # build dist/
npm run test:ci     # run tests (same as CI)
npm audit --audit-level=high
```

Requires Node.js >= 24 (latest LTS). There are no third-party runtime dependencies.

## Updating the workflow pin

The workflow reference is SHA-pinned to a release tag of `reusable-build-test` (with a `# vX.Y.Z` comment). To resolve a new tag to its commit SHA, run the reusable repo's helper script:

```bash
git clone https://github.com/enofei/reusable-build-test.git
./reusable-build-test/scripts/resolve-action-sha.sh enofei/reusable-build-test v1.1.0
# prints: <commit-sha>  # v1.1.0
```

Dependabot also proposes pin updates via weekly PRs.
