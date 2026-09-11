{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "seafile";
  phase = "recovery";
  module = "productivity";
  node.imports = [./node.nix publicModules.nginx];
  script = ./scenario.py;
}
