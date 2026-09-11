{
  lib,
  mkSystem,
  hasFailedAssertion,
  publicModules,
}: let
  bare = (mkSystem publicModules.wireguard).config;
  empty = (mkSystem [publicModules.wireguard {nixstead.services.wireguard.enable = true;}]).config;
  rejectsPath = path:
    !(builtins.tryEval
      (mkSystem [
        publicModules.wireguard
        {
          nixstead.services.wireguard.interfaces.work.configFile = path;
        }
      ]).config.nixstead.services.wireguard.interfaces.work.configFile).success;
  shared = {
    nixstead.services.wireguard = {
      enable = true;
      interfaces.work = {
        configFile = "/run/credentials/work.conf";
        allowedUDPPorts = [51830];
      };
      interfaces.disabled = {
        enable = false;
        configFile = "/run/unused";
      };
      namespaces.apps = {
        configFile = "/run/credentials/apps.conf";
        autostart = false;
        services = ["fixture"];
        hostAccess.tcpPorts = [12345];
      };
      namespaces.disabled.enable = false;
    };
    systemd.services.fixture.serviceConfig.ExecStart = "/bin/true";
  };
  configured = (mkSystem [publicModules.wireguard shared]).config;
  arr =
    (mkSystem [
      publicModules.arr
      {
        nixstead.services.arr.qbittorrent = {
          enable = true;
          vpn.enable = true;
        };
      }
    ]).config;
  selectedArr =
    (mkSystem [
      publicModules.arr
      shared
      {
        nixstead.services.arr.qbittorrent = {
          enable = true;
          vpn = {
            enable = true;
            namespace = "apps";
          };
        };
        nixstead.services.wireguard.namespaces.apps = {
          namespaceAddress = "192.168.243.2";
          bridgeAddress = "192.168.243.1";
        };
      }
    ]).config;
in {
  unrelatedModulesWithoutBackend = lib.all (name: !((mkSystem publicModules.${name}).options ? vpnNamespaces)) [
    "base"
    "secrets"
    "tools"
    "media"
    "dev"
    "localai"
    "productivity"
    "vaultwarden"
    "homeassistant"
    "authentik"
    "syncthing"
    "scrutiny"
    "tailscale"
    "cifs"
    "nas"
    "external"
    "nginx"
    "homepage"
  ];
  backendAvailableToConsumers = lib.all (name: (mkSystem publicModules.${name}).options ? vpnNamespaces) [
    "default"
    "services"
    "arr"
    "wireguard"
    "profile-development"
    "profile-full"
    "profile-media-server"
    "profile-minimal"
  ];
  storeFileRejected = rejectsPath "/nix/store/plaintext.conf";
  unnormalizedFileRejected = rejectsPath "/run/../tmp/tunnel.conf";
  shellSyntaxRejected = rejectsPath "/run/tunnel;command.conf";
  standaloneWithoutArr = !(bare.nixstead.services ? arr);
  disabledCreatesNoTunnels = bare.vpnNamespaces == {} && bare.networking.wg-quick.interfaces == {};
  parentCreatesNoImplicitTunnels = empty.vpnNamespaces == {} && empty.networking.wg-quick.interfaces == {};
  nativeHostTunnel =
    configured.networking.wg-quick.interfaces.work.configFile
    == "/run/credentials/work.conf"
    && configured.networking.firewall.allowedUDPPorts == [51830]
    && configured.systemd.services.wg-quick-work.serviceConfig.UMask == "0077";
  independentDisable = !(configured.vpnNamespaces ? disabled) && !(configured.networking.wg-quick.interfaces ? disabled);
  serviceConfinement =
    configured.systemd.services.fixture.serviceConfig.NetworkNamespacePath
    == "/run/netns/apps"
    && lib.elem "apps.service" configured.systemd.services.fixture.bindsTo
    && lib.elem "apps.service" configured.systemd.services.fixture.partOf
    && configured.systemd.services.apps.wantedBy == []
    && lib.hasInfix "-s 192.168.241.1 -p tcp --dport 12345" configured.systemd.services.apps.postStart
    && configured.vpnNamespaces.apps.portMappings == []
    && configured.vpnNamespaces.apps.allowedEgress == []
    && builtins.isString configured.system.build.toplevel.drvPath;
  arrDelegatesDefault =
    arr.nixstead.services.wireguard.enable
    && arr.nixstead.services.wireguard.namespaces.nixqvpn.sopsSecret == "qbittorrent/wireguard"
    && lib.elem "nixqvpn.service" arr.sops.secrets."qbittorrent/wireguard".restartUnits
    && arr.sops.secrets."qbittorrent/wireguard".mode == "0400"
    && arr.systemd.services.qbittorrent.vpnConfinement.vpnNamespace == "nixqvpn";
  arrUsesSelectedNamespace =
    !(selectedArr.vpnNamespaces ? nixqvpn)
    && selectedArr.services.qbittorrent.serverConfig.Preferences.WebUI.Address == "192.168.243.2"
    && selectedArr.systemd.services.qbittorrent.vpnConfinement.vpnNamespace == "apps"
    && lib.hasInfix "192.168.243.2:8080" selectedArr.systemd.services.nixstead-qbittorrent-proxy.serviceConfig.ExecStart;
  sourceRequired = hasFailedAssertion [
    publicModules.wireguard
    {
      nixstead.services.wireguard = {
        enable = true;
        interfaces.work = {};
      };
    }
  ] "exactly one runtime";
  sourceAmbiguityRejected = hasFailedAssertion [
    publicModules.wireguard
    {
      nixstead.services.wireguard = {
        enable = true;
        interfaces.work = {
          configFile = "/run/work.conf";
          sopsSecret = "wireguard/work";
        };
      };
    }
  ] "exactly one runtime";
  duplicateNetworksRejected = hasFailedAssertion [
    publicModules.wireguard
    shared
    {
      nixstead.services.wireguard.namespaces.other.configFile = "/run/other.conf";
    }
  ] "distinct IPv4 /24";
  duplicateAttachmentRejected = hasFailedAssertion [
    publicModules.wireguard
    shared
    {
      nixstead.services.wireguard.namespaces.other = {
        configFile = "/run/other.conf";
        services = ["fixture"];
      };
    }
  ] "only one WireGuard namespace";
  addressMismatchRejected = hasFailedAssertion [
    publicModules.wireguard
    shared
    {
      nixstead.services.wireguard.namespaces.apps.bridgeAddress = "192.168.242.1";
    }
  ] "same IPv4 /24";
  disabledNamespaceRejectedByArr = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr.qbittorrent = {
        enable = true;
        vpn.enable = true;
      };
      nixstead.services.wireguard.namespaces.nixqvpn.enable = false;
    }
  ] "requires an enabled shared";
}
