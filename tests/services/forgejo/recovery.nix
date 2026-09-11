{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "forgejo";
  phase = "recovery";
  module = "dev";
  node = ./node.nix;
  script = ../../lib/git-forge-scenario.py;
}
