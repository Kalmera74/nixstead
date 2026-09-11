{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.services.tailscale;
in {
  options.nixstead.services.tailscale = {
    enable = lib.mkEnableOption "Tailscale service";

    useRoutingFeatures = lib.mkOption {
      type = lib.types.enum ["none" "client" "server" "both"];
      default = "none";
    };

    advertiseRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      inherit (cfg) useRoutingFeatures;
      extraSetFlags = lib.optional (cfg.advertiseRoutes != []) "--advertise-routes=${lib.concatStringsSep "," cfg.advertiseRoutes}";
    };
  };
}
