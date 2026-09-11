{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "actualbudget";
  phase = "recovery";
  module = "productivity";
  node = import ./node.nix {dynamic = true;};
  script = ./scenario.py;
}
