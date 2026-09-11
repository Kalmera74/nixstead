{
  stateful = true;
  paths = ["modules/services/productivity/wallabag.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Independent enable/disable and parent override, custom published listener/state volumes, private dependencies, runtime SOPS templates, backup database wiring, proxy/card/firewall and invalid port/image inputs.";
    };
    recovery = {
      file = ./recovery.nix;
      systems = ["x86_64-linux"];
      quick = true;
      weight = 3;
      covers = ["runtime" "recovery"];
      detail = "The exact digest-pinned stack reaches its loopback endpoint, then the shipped backup tool captures MariaDB and application files and one clean Borg restore returns it with an exact marker.";
    };
  };
  limitations = ["The combined startup/recovery check is intentionally a fast service-wiring smoke on x86_64. Accounts, saved pages, remote content handling, ARM runtime and pinned upgrades remain unverified." "Redis is treated as a disposable cache; durable Wallabag state is the MariaDB database and application image directory."];
}
