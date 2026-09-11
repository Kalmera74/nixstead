{
  stateful = false;
  paths = ["modules/services/homepage/"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Selected and disabled cards/widgets, custom endpoint/domain/shortcut, runtime placeholders/environment templates, allowed hosts and native listener/proxy/firewall.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    quick = true;
    covers = ["runtime"];
    detail = "The native dashboard and a bounded TrueNAS widget peer start; the configured card, shortcut, placeholder and authenticated widget response render successfully.";
  };
  limitations = ["The widget peer implements only the exact legacy TrueNAS REST endpoints exercised locally. Credential rotation, dependency outages, restart/reboot, browser layout/accessibility, other widget types, live TrueNAS/WebSocket API compatibility, ARM runtime and upgrades are unverified."];
}
