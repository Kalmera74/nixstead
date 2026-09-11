{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "grafana";
  phase = "recovery";
  module = "dev";
  node = ./node.nix;
  script = ./scenario.py;
}
