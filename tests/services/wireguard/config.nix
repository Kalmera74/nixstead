{
  mkSystem,
  lib,
  ...
}: let
  shared = {
    nixstead.services.wireguard = {
      enable = true;
      interfaces.work = {
        sopsSecret = "wireguard/work";
        allowedUDPPorts = [51830];
      };
      interfaces.disabled = {
        enable = false;
        configFile = "/run/unused.conf";
      };
      namespaces.apps = {
        configFile = "/run/credentials/apps.conf";
        autostart = false;
        services = ["fixture"];
        hostAccess.tcpPorts = [12345];
      };
    };
    systemd.services.fixture.serviceConfig.ExecStart = "/bin/true";
  };
  c = (mkSystem [shared]).config;
  disabled = (mkSystem [shared {nixstead.services.wireguard.enable = lib.mkForce false;}]).config;
  empty = (mkSystem [{nixstead.services.wireguard.enable = true;}]).config;
  namespaceSecret =
    (mkSystem [
      shared
      {
        nixstead.services.wireguard.namespaces.apps = {
          configFile = lib.mkForce null;
          sopsSecret = "wireguard/apps";
          autostart = lib.mkForce true;
        };
      }
    ]).config;
  rejectsSource = settings:
    lib.any (a: !a.assertion && lib.hasInfix "requires exactly one runtime" a.message)
    (mkSystem [
      {
        nixstead.services.wireguard = {
          enable = true;
          interfaces.work = settings;
        };
      }
    ]).config.assertions;
  rejectsPath = path: !(builtins.tryEval (mkSystem [{nixstead.services.wireguard.interfaces.work.configFile = path;}]).config.nixstead.services.wireguard.interfaces.work.configFile).success;
in {
  nativeHostInterface = c.networking.wg-quick.interfaces.work.configFile == c.sops.secrets."wireguard/work".path && c.systemd.services.wg-quick-work.serviceConfig.UMask == "0077";
  runtimeKeyRotation = c.sops.secrets."wireguard/work".mode == "0400" && c.sops.secrets."wireguard/work".restartUnits == ["wg-quick-work.service"];
  namespaceEncryptedSource = namespaceSecret.vpnNamespaces.apps.wireguardConfigFile == namespaceSecret.sops.secrets."wireguard/apps".path;
  namespacePrivateRotation = namespaceSecret.sops.secrets."wireguard/apps".mode == "0400" && namespaceSecret.sops.secrets."wireguard/apps".restartUnits == ["apps.service"];
  namespaceExplicitBootStart = lib.elem "multi-user.target" namespaceSecret.systemd.services.apps.wantedBy;
  runtimeNamespaceFilePreserved = c.vpnNamespaces.apps.wireguardConfigFile == "/run/credentials/apps.conf" && !(c.sops.secrets ? "wireguard/apps");
  disabledRemovesTunnelsAndSecrets = disabled.networking.wg-quick.interfaces == {} && disabled.vpnNamespaces == {} && !(disabled.sops.secrets ? "wireguard/work") && !(lib.elem 51830 disabled.networking.firewall.allowedUDPPorts);
  noImplicitTunnels = empty.networking.wg-quick.interfaces == {} && empty.vpnNamespaces == {};
  childDisable = !(c.networking.wg-quick.interfaces ? disabled);
  explicitHandshakeFirewall = lib.elem 51830 c.networking.firewall.allowedUDPPorts && !(lib.elem 12345 c.networking.firewall.allowedTCPPorts);
  namespaceLifecycle = c.systemd.services.fixture.serviceConfig.NetworkNamespacePath == "/run/netns/apps" && lib.elem "apps.service" c.systemd.services.fixture.bindsTo && lib.elem "apps.service" c.systemd.services.fixture.partOf && c.systemd.services.apps.wantedBy == [];
  noImplicitForwarding = c.vpnNamespaces.apps.portMappings == [] && c.vpnNamespaces.apps.allowedEgress == [] && lib.hasInfix "-s 192.168.241.1 -p tcp --dport 12345" c.systemd.services.apps.postStart;
  missingSourceRejected = rejectsSource {};
  ambiguousSourceRejected = rejectsSource {
    configFile = "/run/work.conf";
    sopsSecret = "wireguard/work";
  };
  unsafeRuntimePathsRejected = lib.all rejectsPath ["/nix/store/private.conf" "/run/../tmp/work.conf" "/run/file;command"];
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
}
