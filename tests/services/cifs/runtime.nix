{
  pkgs,
  publicModules,
}:
pkgs.testers.runNixOSTest {
  name = "nixstead-cifs-native-peer";
  node.pkgsReadOnly = false;
  requiredFeatures.kvm = false;
  globalTimeout = 1200;
  nodes = import ./nodes.nix {inherit pkgs publicModules;};
  testScript = builtins.readFile ./scenario.py;
}
