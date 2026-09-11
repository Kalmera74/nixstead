{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "kiwix";
  phase = "runtime";
  module = "media";
  node = ./node.nix;
  script = ./scenario.py;
}
