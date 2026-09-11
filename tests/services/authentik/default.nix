{
  stateful = true;
  paths = ["modules/services/authentik.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Isolated server/worker/database bootstrap, custom SQL port, private internal listeners, native state/mounts, secret ownership/rotation and combined SQL/state archive.";
    };
    recovery = {
      file = ./recovery.nix;
      systems = ["x86_64-linux"];
      weight = 5;
      covers = ["runtime" "recovery"];
      detail = "One shipped Borg backup/restore of native PostgreSQL and state roots, checking readiness and explicit test-owned SQL/file markers.";
    };
  };
  limitations = ["Application identity/provider workflows, repeated lifecycle, outage matrices, proxy interactions and cross-version recovery are outside this wiring smoke fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only."];
}
