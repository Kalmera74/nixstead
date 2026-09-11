{
  stateful = false;
  paths = ["modules/services/external.nix" "modules/services/pihole-dns-sync.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Remote endpoint/admin/API proxy and DNS-sync opt-in profiles, private runtime DNS/widget credentials, Pi-hole widget revision, disabled removal and no local upstream.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "The shipped opt-in DNS sync starts, authenticates to a bounded local Pi-hole v6 API peer and applies the configured owned records once.";
  };
  limitations = ["The local peer implements only the Pi-hole v6 authentication and DNS-host configuration endpoints used by the adapter. Idempotence, credential rotation, failure handling, reboot, live Pi-hole compatibility, appliance databases/recovery, DNS query behavior, ARM runtime and upgrades remain outside this smoke."];
}
