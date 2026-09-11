{lib, ...}: {
  imports = [
    ./backups.nix
    ./service-smoke-tests.nix
    ./tools.nix
    ./locale.nix
    ./networking.nix
    ./nix.nix
    ./user.nix
  ];
}
