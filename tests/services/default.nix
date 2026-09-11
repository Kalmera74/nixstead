{lib}: let
  entries = builtins.readDir ./.;
  directories = lib.filterAttrs (name: type: type == "directory" && builtins.pathExists (./. + "/${name}/default.nix")) entries;
in
  lib.mapAttrs (name: _: import (./. + "/${name}/default.nix")) directories
