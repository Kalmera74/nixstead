{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "openwebui";
  phase = "recovery";
  module = "localai";
  node = ./node.nix;
  script = ./scenario.py;
}
