{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.system;
in {
  options.nixstead.system = {
    allowUnfree = lib.mkEnableOption "unfree packages for this host";
    autoOptimiseStore = lib.mkEnableOption "automatic Nix store optimization";
    cleanTmpOnBoot = lib.mkEnableOption "removing temporary files during boot";
    zram = lib.mkEnableOption "compressed zram swap";

    garbageCollection = {
      enable = lib.mkEnableOption "automatic Nix garbage collection";
      dates = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "systemd calendar expression used for automatic Nix garbage collection.";
      };
      deleteOlderThan = lib.mkOption {
        type = lib.types.strMatching "[1-9][0-9]*[dhm]";
        default = "30d";
        description = "Age threshold passed to nix-collect-garbage --delete-older-than.";
      };
    };
  };

  config = {
    nix.settings.experimental-features = lib.mkDefault ["nix-command" "flakes"];
    nix.settings.auto-optimise-store = cfg.autoOptimiseStore;
    nixpkgs.config.allowUnfree = cfg.allowUnfree;
    boot.tmp.cleanOnBoot = cfg.cleanTmpOnBoot;
    zramSwap.enable = cfg.zram;
    nix.gc = lib.mkIf cfg.garbageCollection.enable {
      automatic = true;
      inherit (cfg.garbageCollection) dates;
      options = "--delete-older-than ${cfg.garbageCollection.deleteOlderThan}";
    };
  };
}
