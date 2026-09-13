# Development checks and generated documentation

Run affected checks first. These commands never activate a host configuration:

```sh
nix fmt -- --fail-on-change
nix develop path:.#ci --command bash scripts/check-source.sh
nix develop path:.#ci --command actionlint
nix build --no-link -L path:.#checks.x86_64-linux.python \
  path:.#checks.x86_64-linux.service-docs path:.#checks.x86_64-linux.test-catalogue
for check in ci-base ci-arr ci-media ci-template; do
  nix eval --option allow-import-from-derivation false --raw \
    "path:.#checks.x86_64-linux.$check.drvPath"
done
```

`nix fmt` coordinates Alejandra, Ruff format and shfmt through treefmt.
ShellCheck is a separate validation step. Keep broad formatting changes separate
from behavioral changes in review and commits. The repository does not authorize
agents to create commits or activate a system by running these checks.

The automatic GitHub Actions workflow runs on pushes to `dev` and `master` and
PRs targeting either branch. Three parallel jobs check formatting and lint,
execute Python and documentation/catalogue checks, and evaluate a small set of
representative configurations plus repository hosts and the CLI/setup packages.
Configuration evaluations run in separate processes to release memory between
them. Each working job has a fifteen-minute timeout. The final `CI passed` job
requires all three to succeed. See [CI and promotion](ci-cd.md) for GitHub branch
protection, auto-merge, the time budget and the normal `dev` to `master` cycle.

The full public API check and service/VM matrix remain outside automatic CI.
A blanket `nix flake check --no-build` is deliberately avoided because Nix still
evaluates every derivation exposed under `checks`. The public API check alone
also retains many evaluated configurations in memory.

The separate heavy workflow runs only by manual dispatch. It builds the x86_64
configuration, Python, catalogue, documentation, credential and source checks,
and the ARM configuration checks. Its runtime scope can include all runtime
checks, only the canaries or one registry service. A full run collapses shared
fixtures through their common execution key and packs the resulting 53
executions into at most 8 weighted runner jobs. Checks are sequential within
each runner, reusing that runner's Nix store. Runtime jobs require KVM on x86_64
and upload their log when they fail. See the [support matrix](support-matrix.md)
for exact coverage.
Actions must run on the remote repository before claiming a successful CI run;
local checks establish local results only.

See [service suite authoring and commands](../tests/README.md) and the
[generated test coverage catalogue](generated/test-coverage.md). The packaged
Python check supplies real Redis, SQLite and credential tools, avoiding
dependency-based skips from a narrower development shell.
Cross-version upgrades remain a visible gap. Ordinary host rebuilds still do
not automatically run these checks.

For broader validation on a machine with sufficient memory and disk:

```sh
nix build --no-link -L path:.#checks.x86_64-linux.public-module-api
nix build --no-link -L path:.#checks.x86_64-linux.service-config
nix develop --command bash tests/test-service-credentials.sh
nix flake check path:. --no-build
```

Generate the service reference from registry metadata:

```sh
nix eval --json .#lib.serviceRegistry > /tmp/nixstead-registry.json
python scripts/generate-service-docs.py /tmp/nixstead-registry.json docs/generated/services.md
```

`checks.<system>.service-docs` rejects drift. Public options come directly from
Nix option definitions: `nix build .#option-docs` produces the JSON option
reference in `result/share/doc/nixos/options.json`. This artifact is generated
from the current source rather than maintained as a second handwritten schema.
Service guides remain required for operational choices and limitations.

Renovate proposes dependency and lockfile updates, including pinned container
digests. The configuration disables automatic merging. A maintainer must enable
the Renovate GitHub app and review resulting PRs; adding configuration alone
does not install or authorize the app.

## Service startup and recovery checks

Run the dedicated check for the changed service, for example:

```sh
nix build --no-link -L path:.#checks.x86_64-linux.service-nextcloud-recovery
nix build --no-link -L path:.#checks.x86_64-linux.service-nginx-runtime
```

A stateful recovery check uses one disposable VM for initial startup/readiness,
one encrypted backup, deletion of its owned storage, and one clean Borg restore.
The restored service must become ready and retain the fixture's independent
marker. Runtime-only checks cover services without a selected recovery policy.
ARR services share one bounded startup/recovery fixture. The selector schedules
shared fixtures once. See the [support matrix](support-matrix.md) for current
results and limits. These checks never switch the development host.
