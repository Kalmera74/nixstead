{
  mkSystem,
  lib,
  ...
}: let
  c =
    (mkSystem [
      {
        nixstead.services.tailscale = {
          enable = true;
          useRoutingFeatures = "both";
          advertiseRoutes = ["192.0.2.0/24" "198.51.100.0/24"];
        };
      }
    ]).config;
  disabled = (mkSystem []).config;
  empty = (mkSystem [{nixstead.services.tailscale.enable = true;}]).config;
in {
  enabledAlone = c.services.tailscale.enable && c.nixstead.serviceRegistry.tailscale.enabled && !c.nixstead.host.user.enable;
  disabledRemovesDaemon = !disabled.services.tailscale.enable && !(disabled.systemd.services ? tailscaled);
  nativeRoutingSelection = c.services.tailscale.useRoutingFeatures == "both";
  advertisedRoutes = c.services.tailscale.extraSetFlags == ["--advertise-routes=192.0.2.0/24,198.51.100.0/24"];
  noImplicitRoutes = empty.services.tailscale.useRoutingFeatures == "none" && empty.services.tailscale.extraSetFlags == [];
  noImplicitEnrollmentSecret = c.services.tailscale.authKeyFile == null;
  invalidRoutingModeRejected = !(builtins.tryEval (mkSystem [{nixstead.services.tailscale.useRoutingFeatures = "invalid";}]).config.nixstead.services.tailscale.useRoutingFeatures).success;
  noHttpProxyOrCard = c.nixstead.serviceRegistry.tailscale.proxy == null && c.nixstead.serviceRegistry.tailscale.homepage == null;
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
}
