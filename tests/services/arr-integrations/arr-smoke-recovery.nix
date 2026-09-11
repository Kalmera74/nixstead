{
  pkgs,
  publicModules,
}:
import ./arr-smoke.nix {
  inherit pkgs publicModules;
  phase = "recovery";
}
