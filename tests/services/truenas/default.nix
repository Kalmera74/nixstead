{
  stateful = false;
  paths = ["modules/services/external.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Remote endpoint, websocket proxy, card/key placeholders, disabled removal, invalid port and absence of local upstream/firewall/storage mounts.";
  };
  checks.runtime = {
    file = ../homepage/runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Homepage and a bounded TrueNAS peer start, and one authenticated widget status/alert response succeeds with the runtime SOPS key.";
  };
  limitations = ["The local peer implements only the exact legacy REST endpoints consumed by the Homepage widget. Credential rotation, dependency failures, restart/reboot, live appliance compatibility, pool/snapshot recovery, storage mounts, ARM runtime and upgrades remain outside this smoke."];
}
