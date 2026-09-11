{
  stateful = true;
  paths = ["modules/services/scrutiny.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Isolated native web/collector/InfluxDB selection and ports, read-only path overrides rejected, private database and combined two-directory archive.";
    };
    recovery = {
      file = ./recovery.nix;
      systems = ["x86_64-linux"];
      covers = ["runtime" "recovery"];
      detail = "One shipped Borg backup and empty-state restore of both native state directories, checking readiness and independent test-owned file markers.";
    };
  };
  limitations = ["SMART report ingestion, historical metrics, physical disk access and repeated lifecycle or outage scenarios are outside this wiring smoke fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only."];
}
