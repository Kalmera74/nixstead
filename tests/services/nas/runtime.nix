{
  pkgs,
  publicModules,
}:
pkgs.testers.runNixOSTest {
  name = "nixstead-nas-runtime";
  node.pkgsReadOnly = false;
  requiredFeatures.kvm = false;
  nodes.machine = import ./node.nix {inherit pkgs publicModules;};
  testScript = builtins.readFile ./scenario.py;
}
