# Compatibility and recovery

The recommended first media configuration is `media-starter`. Runtime and
recovery coverage vary by service; check the [support matrix](support-matrix.md)
before relying on a backup policy.

## Tested baseline and architectures

The supported evaluation baseline is the exact `nixos-unstable` input recorded
in `flake.lock`, together with its locked sops-nix and VPN inputs and registry
container digests. CI evaluates public modules on `x86_64-linux` and
`aarch64-linux`. Runtime jobs target `x86_64-linux` only. ARM runtime, stable
Nixpkgs overrides, alternate database versions, package overrides and arbitrary
container replacements are unverified combinations.

Record the repository and Nixpkgs revisions with verification results.
Evaluation, boot, API integration, and populated restore are separate levels.
A backup entry or successful Borg extraction does not confer restore support.

## Configuration and state changes

Document option renames, changed defaults and preset membership in the affected
technical guide, with a before/after configuration. For state changes, record the
application version, source/target schema, migration command, backup requirement
and rollback limitations.
`system.stateVersion` stays at the host's original value; it is not an upgrade knob.

Pin a revision and keep the previous lock file. Before upgrading, make
and rehearse a backup on disposable state. A NixOS generation rollback does not
reverse database migrations. Restore a matching data snapshot and package
version when upstream state cannot be downgraded. Container/database major
upgrades require their own migration procedure.

## Recovery and update verification

To verify service recovery, create meaningful data via its API, back up with the
shipped helper, restore into empty application/database state, authenticate/read
the data, and repeat after reboot. Retain check output. Identify database engine
fixtures separately from application recovery tests.

Test updates between two pinned revisions, including migrations and recovery.
Record both revisions; a same-version reboot is not an update test. Use the
[installation and update checklist](installation-trial.md) to validate the full
journey on disposable VMs. Cross-version update trials remain unverified until
their results are recorded.
