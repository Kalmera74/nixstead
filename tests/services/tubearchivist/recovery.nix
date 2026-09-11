{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "tubearchivist";
  phase = "recovery";
  module = "media";
  node = ./node.nix;
  script = ./scenario.py;
}
