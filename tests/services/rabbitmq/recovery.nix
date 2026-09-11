{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "rabbitmq";
  phase = "recovery";
  module = "dev";
  node = ./node.nix;
  script = ./scenario.py;
}
