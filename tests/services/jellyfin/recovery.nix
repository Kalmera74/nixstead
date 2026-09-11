{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "jellyfin";
  phase = "recovery";
  module = "media";
  node = ./node.nix;
  script = ./scenario.py;
}
