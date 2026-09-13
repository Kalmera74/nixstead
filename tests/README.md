# Service suites

Each suite is a small collection of independently runnable flake checks. All 66
registry entries have dedicated configuration suites. The
[generated coverage catalogue](../docs/generated/test-coverage.md) includes every
registry service, shared evidence and explicit gaps. It describes test intent;
[the support matrix](../docs/support-matrix.md) records verified scope.

Service-specific descriptors record implemented assertions and outstanding
runtime, recovery, integration and upgrade requirements. A configuration suite
does not complete a service's lifecycle or recovery work.

```sh
# Fast contracts, with no VM boot
nix build --no-link -L path:.#checks.x86_64-linux.service-config

# A single phase, or all checks declared by this service
nix build --no-link -L path:.#checks.x86_64-linux.service-paperless-config
nix build --no-link -L path:.#checks.x86_64-linux.service-paperless-recovery
nix build --no-link -L path:.#checks.x86_64-linux.service-paperless
```

Checks build disposable systems and never activate the development host. Nix
caches successful checks by their dependencies. First builds can download large
closures; VM execution targets KVM-capable x86_64 builders. Configuration is
checked on x86_64 and ARM; application runtime checks currently execute only on
x86_64.

## Layout and coverage contracts

- `services/<registry-id>/default.nix` declares statefulness, owned module paths,
  named checks, precise evidence and limitations. Discovery is automatic.
- `services/<id>/config.nix` checks the public module's enable/disable behavior,
  parent overrides, dependencies, custom paths/ports and applicable wiring.
- `services/<id>/runtime.nix` is used only when startup/readiness is the complete
  applicable scope or no service backup policy exists.
- `services/<id>/recovery.nix` starts the actual stateful service, creates a cheap
  continuity marker, uses the shipped backup command, restores once into empty
  owned storage, and verifies the marker and service readiness.
- `lib/` holds configuration and VM mechanics shared by working scenarios.
- Shared startup/recovery fixtures live with the dedicated service suite that
  owns them. The ARR family uses one fixture under `services/arr-integrations/`
  and exposes it through the affected service checks.

Coverage categories are `configuration`, `runtime`, `persistence`, `recovery`,
`failure` and `upgrade`. One check may provide evidence for several categories;
describe the exact assertions in `detail`. A file alone does not establish a
guarantee. In particular, restarting the same pinned revision is not an upgrade
test. Upgrade scenarios are outside the maintained fast baseline, and no suite
claims full support.
For a genuinely inapplicable category, declare a reason in `notApplicable`, such
as `notApplicable.recovery = "Stateless proxy with no local application data."`.
Missing fixtures should remain missing rather than use this exemption.

Add a suite by following an existing `default.nix`. Configuration checks receive
the helpers from `lib/config.nix` and return named booleans. Other checks receive
`pkgs` and `publicModules`, and return a derivation. Optional `systems` limits a
check to architectures with real fixtures. New checks automatically become
`service-<id>-<check>` flake outputs and enter CI's cost tier (`config` is fast;
other checks are runtime). Set `quick = true` on a small representative runtime
check to include it in the manually selectable canary set. Optional positive
integer `weight` values describe relative runtime cost and balance heavy CI shards;
checks default to weight 1.

Each stateful service supplies readiness, a small marker or bootstrap step,
verification and erasure to `ServiceScenario`. Erasure paths and expected marker
content stay independent of registry backup metadata. Its recovery check covers
the initial real startup as well as one encrypted backup and one clean Borg
restore, then checks readiness and marker continuity after the restore. A
separate runtime VM is omitted because it would repeat the same initial startup.
Runtime-only services keep one startup/readiness check. Recovery does not wait
for the short-lived post-backup restart before beginning restoration. This keeps
the suite focused on Nixstead wiring and avoids repeating application workflows,
failure matrices, restarts and reboots for every service.

Some older service-owned fixtures still make a small application request when
that is the most reliable readiness check. Container archive hashes remain tied
to registry image pins and must be updated when those pins change.

The helper also emits bounded systemd and journal diagnostics on failure.
Registry `backup.requiredFiles` names essential files relative to the primary
archive directory. Additional owned directories each require their own archive
directory. `requiredFilesWhenNull` adds files only when the named service setting
is null, for example a generated password replaced by an external credential
file. `requiredFilesWhenNativeEquals` conditions a requirement on the final
native option value; optional `extraMatches` must also all match.
`requiredFilesFromNativeSQLite` follows the selected SQLite
filename within the primary state root; external paths/engines need separate
recovery contracts. Its `typeOption` can be omitted for known SQLite consumers.
Its optional `pathSuffix` appends a fixed relative filename when the native
option selects a directory rather than the SQLite file itself.
These conditions avoid requiring default-profile files when
a host selects a different native backend.
The default standalone Redis RDB profile additionally uses its selected native
package's checker before accepting or restoring the snapshot.
Opt-in `requiredJsonFiles` and `requiredSQLiteFiles` metadata invokes strict JSON
parsing or an isolated read-only SQLite integrity check for staged primary-slot
files before backup acceptance, rehearsal, or restore mutation. A nonempty SQLite
WAL or rollback journal is rejected because the stopped-writer snapshot has not
been checkpointed; empty companion files are allowed. Validation never modifies
the staged source. `backup.databaseFormat = "custom"` selects a named native
PostgreSQL custom archive whose complete contents are rendered offline with
`pg_restore` before backup acceptance or restore mutation. Other PostgreSQL
policies retain their existing plain SQL format.
Keep service checks at this wiring boundary. Readiness must come from the real
service, and restore markers must be independent of registry backup metadata.
Do not add business workflows, failure matrices, repeated restarts or reboots to
the maintained smoke merely to fill catalogue categories. Those categories stay
explicitly missing unless a separate, justified check owns them.

A service may remain available with `support = "limited"`. Claiming `full`
requires explicit statefulness and scenario evidence for configuration, runtime
and failures; stateful services additionally require persistence and recovery.
The catalogue validator enforces this minimum, while reviewers must assess the
meaning of the scenarios and passing execution evidence. Unknown statefulness
is not treated as stateless. External/hardware limitations remain visible.

## Catalogue and CI

```sh
nix eval --json path:.#lib.testCatalogue > /tmp/nixstead-test-catalogue.json
python tests/suite_catalogue.py /tmp/nixstead-test-catalogue.json docs/generated/test-coverage.md
nix build --no-link path:.#checks.x86_64-linux.test-catalogue

# Inspect affected checks, quick canaries or all service smokes
python tests/select_checks.py /tmp/nixstead-test-catalogue.json --base main --head HEAD --quick
python tests/select_checks.py /tmp/nixstead-test-catalogue.json --canaries
python tests/select_checks.py /tmp/nixstead-test-catalogue.json --service paperless
python tests/select_checks.py /tmp/nixstead-test-catalogue.json --all
# Group a full run into at most 8 balanced runner jobs
python tests/select_checks.py /tmp/nixstead-test-catalogue.json --all --shards 8
# Empty until a runtime fixture has independent ARM execution evidence
python tests/select_checks.py /tmp/nixstead-test-catalogue.json --all --system aarch64-linux
```

Pushes to `dev` and `master`, and PRs targeting either branch, run formatting,
source/workflow lint, the packaged Python tests and catalogue/document drift
checks. They evaluate the `ci-base`, `ci-arr`, `ci-media` and `ci-template`
configuration derivations individually, then the main packages and discovered
hosts. The final `CI passed` status requires all automatic jobs to succeed.
See [CI and promotion](../docs/ci-cd.md) for the required scope and branch setup.
Automatic CI deliberately avoids the full public API check and
`nix flake check --no-build`, which still evaluates every service and runtime
VM derivation. Full API/configuration, credential and runtime checks run in the
manually dispatched heavy workflow, which also repeats the shared Python and
documentation checks. Manual dispatch can run all
runtime checks, the canaries or one registry service. The heavy workflow packs
the 53 unique executions into at most 8 weighted runner jobs; checks run
sequentially inside each runner and reuse its Nix store. Checks backed by the
same fixture file share an execution key and run only once. Selection respects
each check's declared architecture. The full run exposes existing gaps; it
cannot execute upgrade scenarios that do not exist.

The selector is conservative, not a Nix dependency analyser. Keep suite `paths`
accurate and associate shared fixture files with every service they exercise.
No rebuild gate is installed by these suites.
