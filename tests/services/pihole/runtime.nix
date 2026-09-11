{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "pihole";
  phase = "runtime";
  module = "homepage";
  node = ./node.nix;
  script = ./scenario.py;
}
