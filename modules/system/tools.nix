{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixstead.tools;
  tools = import ../../scripts/package.nix {
    inherit pkgs;
    repositoryRoot = config.nixstead.host.repositoryPath;
    configurationName = config.nixstead.host.configurationName;
  };
in {
  options.nixstead.tools = {
    enable = lib.mkEnableOption "the grouped Nixstead administration command";

    media.enable = lib.mkEnableOption "Nixstead media and library subcommands with their heavier runtime dependencies";
  };

  config.environment.systemPackages = lib.optional (cfg.enable || cfg.media.enable) (
    if cfg.media.enable
    then tools.fullCli
    else tools.adminCli
  );
}
