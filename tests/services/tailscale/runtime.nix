{
  pkgs,
  publicModules,
}:
pkgs.testers.runNixOSTest {
  name = "nixstead-tailscale-startup";
  node.pkgsReadOnly = false;
  requiredFeatures.kvm = false;
  nodes.machine = {
    imports = [publicModules.tailscale];
    system.stateVersion = "26.05";
    nixstead.services.tailscale.enable = true;
    environment.systemPackages = [pkgs.tailscale pkgs.jq];
    virtualisation.memorySize = 768;
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("tailscaled.service")
    machine.wait_until_succeeds("tailscale status --json | jq -e '.BackendState == \"NeedsLogin\" and (.TailscaleIPs | length == 0)' >/dev/null")
    machine.succeed("test -S /run/tailscale/tailscaled.sock")
  '';
}
