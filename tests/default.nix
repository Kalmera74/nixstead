{
  nixpkgs,
  pkgs,
  publicModules,
  system,
}: let
  inherit (nixpkgs) lib;
  suites = import ./services {inherit lib;};
  helpers = import ./lib/config.nix {inherit nixpkgs publicModules system;};
  supported = check: lib.elem system (check.systems or ["x86_64-linux" "aarch64-linux"]);
  checks =
    lib.foldlAttrs (
      all: id: suite:
        all
        // lib.mapAttrs' (phase: check:
          lib.nameValuePair "service-${id}-${phase}"
          (
            if phase == "config"
            then let
              report = import check.file helpers;
              failures = lib.attrNames (lib.filterAttrs (_: passed: !passed) report);
            in
              assert lib.assertMsg (failures == []) "${id} configuration checks failed: ${lib.concatStringsSep ", " failures}";
                pkgs.writeText "${id}-configuration.json" (builtins.toJSON report)
            else import check.file {inherit pkgs publicModules;}
          )) (lib.filterAttrs (_: supported) suite.checks)
    ) {}
    suites;
in
  checks
  // {
    service-config = pkgs.linkFarm "nixstead-service-config" (lib.mapAttrsToList (id: _: {
        name = id;
        path = checks."service-${id}-config";
      })
      suites);
  }
  // lib.mapAttrs' (id: suite:
    lib.nameValuePair "service-${id}" (pkgs.linkFarm "nixstead-${id}-suite" (lib.mapAttrsToList (phase: _: {
        name = phase;
        path = checks."service-${id}-${phase}";
      })
      suite.checks))) (lib.filterAttrs (_: suite: lib.all supported (builtins.attrValues suite.checks)) suites)
