{
  pkgs,
  publicModules,
}:
(import ../../lib/service-vm.nix {inherit pkgs publicModules;}) {
  id = "proxmox";
  phase = "runtime";
  module = "homepage";
  node = ./node.nix;
  script = ./scenario.py;
}
