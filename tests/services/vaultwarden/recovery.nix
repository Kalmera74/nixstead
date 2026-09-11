{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "vaultwarden";
  phase = "recovery";
  module = "vaultwarden";
  node = ./node.nix;
  script = ./scenario.py;
}
