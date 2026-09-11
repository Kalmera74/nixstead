{
  pkgs,
  publicModules,
}: {phase}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "syncthing";
  inherit phase;
  module = "syncthing";
  node = ./node.nix;
  script = ./scenario.py;
}
