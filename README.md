# caller-repo

Node.js application using the org reusable workflow ([enofei/reusable-build-test](https://github.com/enofei/reusable-build-test)) for CI.

`.github/workflows/ci.yml`:

```yaml
jobs:
  build-and-test:
    uses: enofei/reusable-build-test/.github/workflows/build-test.yml@59e8e1fb94b462eae54949475096c923b930d592  # v1.0.0
    with:
      node-version: '24'
      test-command: 'npm run test:ci'
      security-checks: true
```

On every pull request to `main`/`develop` it runs `npm ci`, `npm run build`, `npm run test:ci`, and `npm audit --audit-level=high`.

Requires Node.js >= 24. No third-party dependencies.

```bash
npm ci
npm run build
npm run test:ci
```

CI is SHA-pinned to a `reusable-build-test` release tag. Resolve a tag to its commit SHA with that repo's `scripts/resolve-action-sha.sh`; Dependabot also proposes pin updates weekly.

## Branch policy

Work happens on `dev`. `main` accepts only commits with verified signatures — enforced by branch protection with administrators included.
