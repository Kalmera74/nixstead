{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "seerr";
  phase = "recovery";
  module = "media";
  node = import ./node.nix {inherit publicModules;};
  script = ./scenario.py;
}
