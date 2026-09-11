{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "redis";
  phase = "recovery";
  module = "dev";
  node = ./node.nix;
  script = ./scenario.py;
}
