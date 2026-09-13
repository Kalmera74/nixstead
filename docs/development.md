# Development and extension guide

This guide is for contributors changing the repository itself. Read the root
`AGENTS.md` for the current coding-agent conventions as well.

Develop on `dev`, then promote a ready batch through a pull request to protected
`master` with auto-merge enabled. See [CI and promotion](ci-cd.md) for the required
checks, one-time GitHub settings and branch synchronization after each merge.

## Repository principles

- Keep machine facts in host configuration.
- Keep service implementation behavior in concrete service modules.
- Keep repeated service integration facts in the registry.
- Keep program package groups independent from service presets.
- Use child service toggles for Nginx, Homepage, firewall, and health behavior.
- Preserve the encrypted `NIXSTEAD_SECRETS_DIR` override and never evaluate
  plaintext secret values in Nix.
- Use explicit opt-in flags for destructive scripts.

## Adding a host

Prefer the wizard:

```bash
./setup.sh --generate-only
```

Or create:

```text
hosts/<name>/
├── default.nix
└── hardware-configuration.nix
```

The root flake discovers it automatically. The hardware configuration must
declare `nixpkgs.hostPlatform`, and the host must set its original
`system.stateVersion`.

Do not add the host manually to `flake.nix`.

## Adding a service

1. Choose the existing stack that owns it. Create a new stack only when it
   contains at least two related services; otherwise add a standalone
   `modules/services/<service>.nix` module using `nixstead.services.<service>`.
2. Add an entry to the matching file under `modules/services/registry/`.
3. Define the option with `serviceOptionFromRegistry` when its shape is
   compatible.
4. Add a concrete implementation module.
5. Import it from the stack wrapper.
6. Add keys to `secrets/secrets.example.yaml` and declare per-service sops-nix
   files/templates if needed.
7. Confirm generic Nginx/Homepage/firewall/health/DNS/backup rendering.
8. Add custom integration code only for behavior metadata cannot represent.
9. Update `docs/services.md` and the stack README.

Example registry-backed wrapper option:

```nix
example = serviceOptionFromRegistry "example" {
  extraOptions.exampleMode = lib.mkOption {
    type = lib.types.enum ["a" "b"];
    default = "a";
  };
};
```

Example implementation:

```nix
{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.services.example;
in {
  config = lib.mkIf cfg.enable {
    services.example.enable = true;
  };
}
```

Secret-backed implementations must pass runtime paths or sops-nix placeholders,
never decrypted values, to NixOS options. Prefer native `passwordFile` options;
use a root-only SOPS template for `EnvironmentFile` consumers.

## Parent stack behavior

Parent `.enable` switches must set child defaults without preventing a host from
disabling one child. Use default-priority values or option defaults tied to the
parent; never make downstream integration depend only on the parent.

Correct integration condition:

```nix
config.nixstead.services.arr.radarr.enable
```

Incorrect integration condition:

```nix
config.nixstead.services.arr.enable
```

## Registry changes

When changing an option or enable path, audit every resolved registry consumer.
Use the helpers for unusual shapes instead of adding duplicated special-case
lists. See [Central service registry](service-registry.md).

## Public API changes

Names under `nixosModules`, `templates`, and exported `lib` are compatibility
boundaries. Add checks under `tests/` when introducing a public export or an
important behavioral guarantee; `flake.nix` should only expose the resulting
check derivation.

Every `nixosModules` export must have a matching entry in the synthetic closure
matrix in `tests/fixtures/public-closures.nix`. Enable at least one
representative service for stack exports so package-license, user/group, and
service-level assertions are forced. The host template is checked through the
same `system.build.toplevel` path.

Registry endpoint tests must compare configured application listeners and
storage locations with the resolved registry settings. An integration-only
check can pass while the application is still listening on its old value.

Internal module paths can be reorganized, but repository hosts and docs must be
migrated in the same change.

## Shell scripts

Repository scripts should:

- use `#!/usr/bin/env bash` and `set -euo pipefail`;
- provide `usage()` when accepting arguments;
- validate required commands;
- quote paths and variables;
- derive the repository root from the script's actual directory;
- default destructive operations to dry-run/refusal;
- use unpredictable temporary directories; and
- arrange cleanup/recovery traps before mutating data.

Registry-aware scripts should use `scripts/lib/nixstead.sh` instead of
rebuilding flake-reference logic.

## Documentation

- The root README is the product landing page.
- Cross-cutting user workflows belong under `docs/`.
- Directory READMEs explain local ownership and extension patterns.
- Examples must use real current option paths.
- Update links and service catalogs with architecture changes.

## Validation

Run the narrowest relevant check first, then the full checks:

```bash
python3 -m compileall -q setup
python3 -m unittest tests/test_setup.py
bash -n setup.sh scripts/*.sh scripts/lib/*.sh
nix flake check path:.
```

For host behavior:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.services
```

For registry behavior:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.serviceRegistry
```

Inspect `git diff --check` and ensure unrelated user changes remain untouched
before committing.

## Operational validation

See [automated checks and generated documentation](validation.md) for the CI
workflow, formatters, isolated VM groups, and registry documentation drift checks.
