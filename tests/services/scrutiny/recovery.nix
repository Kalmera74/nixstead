{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "scrutiny";
  phase = "recovery";
  module = "scrutiny";
  node = ./node.nix;
  script = ./scenario.py;
}
