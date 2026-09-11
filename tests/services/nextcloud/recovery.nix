{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "nextcloud";
  phase = "recovery";
  module = "productivity";
  node = ./node.nix;
  script = ./scenario.py;
}
