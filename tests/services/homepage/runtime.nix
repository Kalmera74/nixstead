{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "homepage";
  phase = "runtime";
  module = "homepage";
  node = ./node.nix;
  script = ./scenario.py;
}
