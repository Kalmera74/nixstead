{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "audiobookshelf";
  phase = "recovery";
  module = "media";
  node = ./node.nix;
  script = ./scenario.py;
}
