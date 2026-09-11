{
  config,
  lib,
  pkgs,
  ...
}: let
  arr = config.nixstead.services.arr;
  cfg = arr.qbittorrent.vpn;
  namespace =
    if cfg.namespace == null
    then "nixqvpn"
    else cfg.namespace;
  selected =
    config.nixstead.services.wireguard.namespaces.${
      namespace
    } or {
      enable = false;
      namespaceAddress = "127.0.0.1";
    };
  namespaceAddress = selected.namespaceAddress;
in {
  imports = [../wireguard.nix];
  options.nixstead.services.arr.qbittorrent.vpn = {
    enable = lib.mkEnableOption "qBittorrent WireGuard confinement";
    namespace = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[A-Za-z][A-Za-z0-9_-]{0,6}");
      default = null;
      description = "Use an explicitly configured shared WireGuard namespace. Null creates the default nixqvpn namespace through the shared WireGuard module.";
    };
    wireguardConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime wg-quick configuration with Address, DNS, Endpoint and full-tunnel AllowedIPs. Null selects the qbittorrent/wireguard SOPS key.";
    };
  };
  config = lib.mkIf (arr.qbittorrent.enable && cfg.enable) {
    assertions = [
      {
        assertion = config.nixstead.services.wireguard.enable && selected.enable;
        message = "qBittorrent VPN requires an enabled shared WireGuard namespace.";
      }
      {
        assertion = cfg.namespace == null || cfg.wireguardConfigFile == null;
        message = "Configure credentials on the selected shared WireGuard namespace instead of qBittorrent wireguardConfigFile.";
      }
      {
        assertion = config.nixstead.serviceRegistry.qbittorrent.exposure == "loopback";
        message = "Confined qBittorrent uses authenticated loopback access through Nginx; direct application exposure must be loopback.";
      }
    ];
    nixstead.services.wireguard = {
      enable = lib.mkDefault true;
      namespaces.${namespace} = lib.mkMerge [
        (lib.mkIf (cfg.namespace == null) {
          configFile = cfg.wireguardConfigFile;
          sopsSecret =
            if cfg.wireguardConfigFile == null
            then "qbittorrent/wireguard"
            else null;
        })
        {
          services = ["qbittorrent"];
          hostAccess.tcpPorts = [arr.qbittorrent.port];
        }
      ];
    };
    services.qbittorrent.serverConfig.Preferences.WebUI.Address = lib.mkForce namespaceAddress;
    systemd.services = {
      nixstead-qbittorrent-proxy = {
        description = "Authenticated qBittorrent access from host loopback to VPN namespace";
        after = ["qbittorrent.service"];
        requires = ["qbittorrent.service"];
        serviceConfig = {
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${namespaceAddress}:${toString arr.qbittorrent.port}";
          DynamicUser = true;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          RestrictAddressFamilies = ["AF_INET" "AF_UNIX"];
        };
      };
    };
    systemd.sockets.nixstead-qbittorrent-proxy = {
      wantedBy = ["sockets.target"];
      listenStreams = ["127.0.0.1:${toString arr.qbittorrent.port}"];
    };
  };
}
