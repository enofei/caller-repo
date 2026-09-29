# caller-repo

A sample Node.js application that exercises the organization's shared CI pipeline:

**[`enofei/reusable-build-test`](https://github.com/enofei/reusable-build-test)** → `.github/workflows/build-test.yml`

## How CI works

[`ci.yml`](.github/workflows/ci.yml) contains a single job that *calls* the org reusable workflow instead of defining build steps locally:

```yaml
jobs:
  build-and-test:
    uses: enofei/reusable-build-test/.github/workflows/build-test.yml@8acbac233f3f35d5ed829962e12c00eda7373641  # v1.1.0
    with:
      node-version: '20'
      test-command: 'npm run test:ci'
      security-checks: true
```

The reusable workflow then runs, on every pull request to `main` / `develop`:

1. `npm ci` — install from `package-lock.json`
2. `npm run build` — bundle `src/` into `dist/`
3. `npm run test:ci` — Node's built-in test runner
4. `npm audit --audit-level=high` — security audit (`security-checks: true`)

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

Requires Node.js >= 20. There are no third-party runtime dependencies.

## Updating the workflow pin

The workflow reference is SHA-pinned to a release tag of `reusable-build-test` (with a `# vX.Y.Z` comment). To resolve a new tag to its commit SHA, run the reusable repo's helper script:

```bash
git clone https://github.com/enofei/reusable-build-test.git
./reusable-build-test/scripts/resolve-action-sha.sh enofei/reusable-build-test v1.2.0
# prints: <commit-sha>  # v1.2.0
```

Dependabot also proposes pin updates via weekly PRs.
