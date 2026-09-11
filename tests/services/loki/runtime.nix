{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "loki";
  phase = "runtime";
  module = "dev";
  node = ./node.nix;
  script = ./scenario.py;
}
