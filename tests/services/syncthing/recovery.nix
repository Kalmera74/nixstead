{
  pkgs,
  publicModules,
}:
(import ./vm.nix {inherit pkgs publicModules;}) {phase = "recovery";}
