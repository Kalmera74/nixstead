{
  nixpkgs,
  publicModules,
  system,
}: let
  lib = nixpkgs.lib;
  mkSystem = modules:
    nixpkgs.lib.nixosSystem {
      inherit system;
      modules =
        [
          publicModules.default
          {
            system.stateVersion = "26.05";
            boot.loader.grub.devices = ["/dev/vda"];
            fileSystems."/" = {
              device = "/dev/vda1";
              fsType = "ext4";
            };
            nixstead.secrets = {
              enable = true;
              sopsFile = ../../secrets/test.yaml;
            };
          }
        ]
        ++ modules;
    };
in {
  inherit lib mkSystem;
  serviceContract = {
    id,
    group ? null,
    port ? null,
    nativeEnabled,
    extra ? {},
  }: let
    registry = import ../../modules/services/registry.nix;
    entry = registry.${id};
    selected = lib.setAttrByPath (["nixstead" "services"] ++ entry.enablePath) true;
    deselected = lib.setAttrByPath (["nixstead" "services"] ++ entry.enablePath) false;
    portOverride = lib.optionalAttrs (port != null) (lib.setAttrByPath (["nixstead" "services"] ++ entry.optionPath ++ ["port"]) port);
    base = {
      nixstead.services.homepage.enable = true;
      nixstead.services.nginx.enable = true;
    };
    enabled = (mkSystem [base extra selected portOverride]).config;
    disabled = (mkSystem [base extra deselected portOverride]).config;
    parent =
      (mkSystem [
        base
        extra
        portOverride
        deselected
        (lib.optionalAttrs (group != null) (lib.setAttrByPath ["nixstead" "services" group "enable"] true))
      ]).config;
    exposed =
      (mkSystem [
        extra
        selected
        portOverride
        {
          nixstead.host.network.exposure.services.${id} = "public";
        }
      ]).config;
    proxyKey = cfg: entry.proxy.vhostKey or cfg.nixstead.serviceRegistry.${id}.settings.domain;
    cards = cfg: builtins.toJSON cfg.services.homepage-dashboard.services;
  in
    {
      enabledAlone = enabled.nixstead.serviceRegistry.${id}.enabled && nativeEnabled enabled;
      noPersonalAccountRequired = !enabled.nixstead.host.user.enable;
      disabledRemovesImplementation = !disabled.nixstead.serviceRegistry.${id}.enabled && !nativeEnabled disabled;
      validSystem = builtins.isString enabled.system.build.toplevel.drvPath;
    }
    // lib.optionalAttrs (group != null) {
      parentAllowsChildDisable = !parent.nixstead.serviceRegistry.${id}.enabled && !nativeEnabled parent;
    }
    // lib.optionalAttrs (port != null) {
      portOverrideReachesRegistry = enabled.nixstead.serviceRegistry.${id}.settings.port == port;
      loopbackDoesNotOpenFirewall = !(lib.elem port enabled.networking.firewall.allowedTCPPorts);
      publicOpensFirewall = entry.firewall == null || lib.elem port exposed.networking.firewall.allowedTCPPorts;
      disabledClosesFirewall = !(lib.elem port disabled.networking.firewall.allowedTCPPorts);
    }
    // lib.optionalAttrs (entry.proxy != null) {
      enabledHasProxy = enabled.services.nginx.virtualHosts ? ${proxyKey enabled};
      disabledRemovesProxy = !(disabled.services.nginx.virtualHosts ? ${proxyKey disabled}) && !(parent.services.nginx.virtualHosts ? ${proxyKey parent});
    }
    // lib.optionalAttrs (entry.proxy != null && port != null) {
      proxyUsesOverride = lib.hasInfix ":${toString port}" enabled.services.nginx.virtualHosts.${proxyKey enabled}.locations."/".proxyPass;
    }
    // lib.optionalAttrs (entry.homepage != null) {
      enabledHasCard = lib.hasInfix (builtins.toJSON entry.homepage.title) (cards enabled);
      disabledRemovesCard = !lib.hasInfix (builtins.toJSON entry.homepage.title) (cards disabled) && !lib.hasInfix (builtins.toJSON entry.homepage.title) (cards parent);
    };
}
