{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "linkwarden";
  phase = "recovery";
  module = "productivity";
  node = ./node.nix;
  script = ./scenario.py;
}
