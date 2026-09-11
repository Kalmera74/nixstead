{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "authentik";
  phase = "recovery";
  module = "authentik";
  node = ./node.nix;
  script = ./scenario.py;
}
