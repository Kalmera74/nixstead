{
  config,
  lib,
  pkgs,
  secretPath,
  serviceOptionFromRegistry,
  ...
}: let
  cfg = config.nixstead.services.wireguard;
  inherit (lib) types;
  runtimePath = types.addCheck (types.strMatching "/[A-Za-z0-9_./-]+") (path:
    path
    != "/nix/store"
    && !lib.hasPrefix "/nix/store/" path
    && lib.all (part: !lib.elem part ["" "." ".."]) (lib.tail (lib.splitString "/" path)));
  ipv4 =
    types.addCheck (types.strMatching "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+") (address:
      lib.all (part: let value = lib.toInt part; in value <= 255 && toString value == part) (lib.splitString "." address));
  ipv6 =
    types.addCheck (types.strMatching "[0-9A-Fa-f:]+") (address:
      (builtins.tryEval (builtins.deepSeq (lib.network.ipv6.fromString address) true)).success);
  ipv4Network = address: lib.concatStringsSep "." (lib.take 3 (lib.splitString "." address));
  ipv6Address = address: (lib.network.ipv6.fromString address).address;
  ipv6Network = address: lib.concatStringsSep ":" (lib.take 4 (lib.splitString ":" (ipv6Address address)));
  selected = lib.filterAttrs (_: entry: cfg.enable && entry.enable);
  interfaces = selected cfg.interfaces;
  namespaces = selected cfg.namespaces;
  namespaceNames = lib.attrNames namespaces;
  services = lib.concatMap (entry: lib.unique entry.services) (lib.attrValues namespaces);
  uniqueAttachments = lib.length services == lib.length (lib.unique services);
  unitFor = kind: name:
    if kind == "interface"
    then "wg-quick-${name}.service"
    else "${name}.service";
  source = entry:
    if entry.configFile != null
    then entry.configFile
    else if entry.sopsSecret != null
    then secretPath entry.sopsSecret
    else "/run/nixstead-wireguard-unconfigured";
  sourceOptions = {
    enable = lib.mkOption {
      type = types.bool;
      default = cfg.enable;
      description = "Enable this explicitly declared tunnel; can be disabled independently.";
    };
    configFile = lib.mkOption {
      type = types.nullOr runtimePath;
      default = null;
      description = "Absolute runtime wg-quick configuration file outside the Nix store. Select exactly one of configFile and sopsSecret. Paths must be normalized and shell-safe for upstream tools.";
    };
    sopsSecret = lib.mkOption {
      type = types.nullOr (types.addCheck (types.strMatching "[A-Za-z0-9_./-]+") (key: lib.all (part: !lib.elem part ["" "." ".."]) (lib.splitString "/" key)));
      default = null;
      example = "wireguard/work";
      description = "SOPS key containing the complete WireGuard configuration. The generated secret is root-readable and restarts this tunnel on rotation.";
    };
    autostart = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Start the tunnel at boot. An attached service can also start a namespace on demand.";
    };
  };
  checkSources = entries:
    lib.mapAttrsToList (name: entry: {
      assertion = (entry.configFile != null) != (entry.sopsSecret != null) && runtimePath.check (source entry);
      message = "WireGuard ${name} requires exactly one runtime configFile or sopsSecret.";
    })
    entries;
  secretsFor = kind: entries:
    lib.mapAttrsToList (name: entry:
      lib.optionalAttrs (entry.sopsSecret != null) {
        ${entry.sopsSecret} = {
          mode = "0400";
          restartUnits = [(unitFor kind name)];
        };
      })
    entries;
in {
  options.nixstead.services.wireguard = serviceOptionFromRegistry "wireguard" {
    extraOptions = {
      interfaces = lib.mkOption {
        default = {};
        description = "Host WireGuard interfaces using native wg-quick. Routing, peers and DNS are supplied in the runtime configuration.";
        type = types.attrsOf (types.submodule {
          options =
            sourceOptions
            // {
              allowedUDPPorts = lib.mkOption {
                type = types.listOf types.port;
                default = [];
                description = "Explicit host firewall openings for incoming WireGuard handshakes. These must match ListenPort in the runtime configuration.";
              };
            };
        });
      };
      namespaces = lib.mkOption {
        default = {};
        description = "Isolated full-tunnel WireGuard namespaces for selected systemd services, using the pinned VPN-Confinement backend.";
        type = types.attrsOf (types.submodule {
          options =
            sourceOptions
            // {
              namespaceAddress = lib.mkOption {
                type = ipv4;
                default = "192.168.241.2";
                description = "Namespace IPv4 address on its private /24 host bridge.";
              };
              bridgeAddress = lib.mkOption {
                type = ipv4;
                default = "192.168.241.1";
                description = "Host IPv4 address on the namespace's private /24 bridge.";
              };
              namespaceAddressIPv6 = lib.mkOption {
                type = ipv6;
                default = "fd93:9701:241::2";
                description = "Namespace IPv6 address on its private /64 host bridge.";
              };
              bridgeAddressIPv6 = lib.mkOption {
                type = ipv6;
                default = "fd93:9701:241::1";
                description = "Host IPv6 address on the namespace's private /64 bridge.";
              };
              services = lib.mkOption {
                type = types.listOf (types.strMatching "[A-Za-z0-9][A-Za-z0-9_@.-]*");
                default = [];
                example = ["qbittorrent"];
                description = "Existing systemd service names without .service, bound to this namespace's lifecycle and DNS. This does not create or enable application implementations.";
              };
              hostAccess.tcpPorts = lib.mkOption {
                type = types.listOf types.port;
                default = [];
                description = "Namespace TCP ports reachable only from this namespace's host bridge address. No host firewall port or DNAT mapping is created.";
              };
              hostAccess.udpPorts = lib.mkOption {
                type = types.listOf types.port;
                default = [];
                description = "Namespace UDP ports reachable only from this namespace's host bridge address.";
              };
            };
        });
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      checkSources interfaces
      ++ checkSources namespaces
      ++ lib.mapAttrsToList (name: _: {
        assertion = builtins.match "[A-Za-z][A-Za-z0-9_-]{0,14}" name != null;
        message = "WireGuard interface ${name} must have a safe interface name of at most 15 characters.";
      })
      interfaces
      ++ lib.mapAttrsToList (name: entry: {
        assertion =
          builtins.match "[A-Za-z][A-Za-z0-9_-]{0,6}" name
          != null
          && !builtins.hasAttr "${name}0" interfaces
          && !lib.elem name services
          && lib.all (unit: !lib.hasSuffix ".service" unit) entry.services;
        message = "WireGuard namespace ${name} requires a safe name of at most 7 characters, non-conflicting tunnel/service names, and service names without .service.";
      })
      namespaces
      ++ lib.mapAttrsToList (name: entry: {
        assertion =
          entry.namespaceAddress
          != entry.bridgeAddress
          && ipv4Network entry.namespaceAddress == ipv4Network entry.bridgeAddress
          && (!config.networking.enableIPv6 || (ipv6Address entry.namespaceAddressIPv6 != ipv6Address entry.bridgeAddressIPv6 && ipv6Network entry.namespaceAddressIPv6 == ipv6Network entry.bridgeAddressIPv6));
        message = "WireGuard namespace ${name} bridge and namespace addresses must be distinct addresses in the same IPv4 /24 and IPv6 /64.";
      })
      namespaces
      ++ [
        {
          assertion = uniqueAttachments;
          message = "A systemd service can belong to only one WireGuard namespace.";
        }
        {
          assertion =
            lib.length namespaceNames
            == lib.length (lib.unique (map (entry: ipv4Network entry.bridgeAddress) (lib.attrValues namespaces)))
            && (!config.networking.enableIPv6 || lib.length namespaceNames == lib.length (lib.unique (map (entry: ipv6Network entry.bridgeAddressIPv6) (lib.attrValues namespaces))));
          message = "WireGuard namespaces require distinct IPv4 /24 and IPv6 /64 bridge networks.";
        }
      ];

    sops.secrets = lib.mkMerge (secretsFor "interface" interfaces ++ secretsFor "namespace" namespaces);
    networking.wg-quick.interfaces =
      lib.mapAttrs (_: entry: {
        configFile = source entry;
        inherit (entry) autostart;
      })
      interfaces;
    networking.firewall.allowedUDPPorts = lib.concatMap (entry: entry.allowedUDPPorts) (lib.attrValues interfaces);
    vpnNamespaces =
      lib.mapAttrs (_: entry: {
        enable = true;
        inherit (entry) namespaceAddress bridgeAddress namespaceAddressIPv6 bridgeAddressIPv6;
        wireguardConfigFile = source entry;
        accessibleFrom = [];
        allowedEgress = [];
        portMappings = [];
        openVPNPorts = [];
      })
      namespaces;
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (name: _: {
        "wg-quick-${name}".serviceConfig.UMask = "0077";
      })
      interfaces
      ++ lib.mapAttrsToList (name: entry:
        {
          ${name} = {
            wantedBy = lib.mkOverride 90 (lib.optional entry.autostart "multi-user.target");
            postStart = lib.concatStringsSep "\n" (lib.concatMap (
              protocol:
                lib.concatMap (
                  port:
                    ["${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iptables}/bin/iptables -A INPUT -i veth-${name} -s ${entry.bridgeAddress} -p ${protocol} --dport ${toString port} -j ACCEPT"]
                    ++ lib.optional config.networking.enableIPv6 "${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iptables}/bin/ip6tables -A INPUT -i veth-${name} -s ${entry.bridgeAddressIPv6} -p ${protocol} --dport ${toString port} -j ACCEPT"
                )
                entry.hostAccess."${protocol}Ports"
            ) ["tcp" "udp"]);
          };
        }
        // lib.optionalAttrs uniqueAttachments (lib.genAttrs (lib.unique entry.services) (_: {
          vpnConfinement = {
            enable = true;
            vpnNamespace = name;
          };
          partOf = ["${name}.service"];
        })))
      namespaces
    );
  };
}
