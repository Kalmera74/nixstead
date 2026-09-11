{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "stirlingpdf";
  phase = "runtime";
  module = "productivity";
  node = ./node.nix;
  script = ./scenario.py;
}
