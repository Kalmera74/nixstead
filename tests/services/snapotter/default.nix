{
  stateful = true;
  paths = ["modules/services/productivity/snapotter.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent enable/disable and parent override, custom published listener/state volumes, private dependencies, runtime SOPS templates, backup database wiring, proxy/card/firewall and invalid port/image inputs.";
  };
  limitations = ["Native startup and clean restore remain unverified: the exact supported amd64 application image contains about 3.56 GiB of compressed layers, disproportionate to the maintained fast smoke baseline." "No business-workflow, failure, lifecycle or upgrade claim."];
}
