{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "gitea";
  phase = "recovery";
  module = "dev";
  node = ./node.nix;
  script = ../../lib/git-forge-scenario.py;
}
