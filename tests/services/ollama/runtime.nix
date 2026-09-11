{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "ollama";
  phase = "runtime";
  module = "localai";
  node = ./node.nix;
  script = ./scenario.py;
}
