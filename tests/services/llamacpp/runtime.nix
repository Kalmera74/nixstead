{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "llamacpp";
  phase = "runtime";
  module = "localai";
  node = ./node.nix;
  script = ./scenario.py;
}
