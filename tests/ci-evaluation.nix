{
  nixpkgs,
  pkgs,
  publicModules,
  system,
}: let
  inherit (nixpkgs) lib;
  fixtures = import ./fixtures/public-closures.nix {inherit publicModules;};
  # Keep this list small. CI evaluates each derivation in a fresh process;
  # public-module-api retains the exhaustive API and option assertions.
  selected =
    {inherit (fixtures) base arr media;}
    // {
      template = [publicModules.default ../templates/host/configuration.nix];
    };
  evaluate = name: modules: let
    configuration = nixpkgs.lib.nixosSystem {
      inherit system;
      modules =
        lib.toList modules
        ++ [
          {
            nixpkgs.hostPlatform = system;
            boot.loader.grub.devices = ["/dev/vda"];
            fileSystems."/" = {
              device = "/dev/vda1";
              fsType = "ext4";
            };
            system.stateVersion = "26.05";
            nixstead.secrets = {
              enable = true;
              sopsFile = ../secrets/test.yaml;
            };
          }
        ];
    };
    # Discard the string context so building this report cannot build a system.
    systemDrv = builtins.unsafeDiscardStringContext configuration.config.system.build.toplevel.drvPath;
  in
    pkgs.writeText "nixstead-ci-${name}.json" (builtins.toJSON {inherit systemDrv;});
in
  lib.mapAttrs' (name: modules: lib.nameValuePair "ci-${name}" (evaluate name modules)) selected
