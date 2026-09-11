{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "homeassistant";
  phase = "recovery";
  module = "homeassistant";
  node = ./node.nix;
  script = ./scenario.py;
}
