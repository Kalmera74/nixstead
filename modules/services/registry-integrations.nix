{
  config,
  lib,
  ...
}: let
  exposedServices =
    lib.filterAttrs (
      _: entry:
        entry.enabled
        && entry.firewall != null
        && entry.firewall != false
    )
    config.nixstead.serviceRegistry;

  tcpPortsFor = entry: let
    firewall = entry.firewall;
    primary =
      if firewall == true
      then true
      else firewall.primary or false;
    primaryPorts =
      lib.optional (
        primary && entry.settings ? port && entry.settings.port != null
      )
      entry.settings.port;
    staticPorts =
      if builtins.isAttrs firewall
      then firewall.tcpPorts or []
      else [];
    settingsPorts =
      if builtins.isAttrs firewall
      then map (name: entry.settings.${name}) (firewall.settingsTcpPorts or [])
      else [];
    hostPorts =
      if builtins.isAttrs firewall
      then map (name: config.nixstead.host.ports.${name}) (firewall.hostTcpPorts or [])
      else [];
  in
    primaryPorts ++ staticPorts ++ settingsPorts ++ hostPorts;

  udpPortsFor = entry: let
    firewall = entry.firewall;
    staticPorts =
      if builtins.isAttrs firewall
      then firewall.udpPorts or []
      else [];
    settingsPorts =
      if builtins.isAttrs firewall
      then map (name: entry.settings.${name}) (firewall.settingsUdpPorts or [])
      else [];
    hostPorts =
      if builtins.isAttrs firewall
      then map (name: config.nixstead.host.ports.${name}) (firewall.hostUdpPorts or [])
      else [];
  in
    staticPorts ++ settingsPorts ++ hostPorts;

  servicesFor = exposure:
    lib.attrValues (lib.filterAttrs (_: entry: entry.exposure == exposure) exposedServices);
  portsFor = protocol: exposure:
    lib.unique (lib.concatMap (
        if protocol == "tcp"
        then tcpPortsFor
        else udpPortsFor
      )
      (servicesFor exposure));
  publishedPortsFor = protocol: exposure:
    lib.unique (lib.concatMap (
        if protocol == "tcp"
        then tcpPortsFor
        else udpPortsFor
      )
      (lib.filter (entry: entry.containerPublished) (servicesFor exposure)));

  scopedExposures = ["lan" "tailnet"];
  selectorFor = exposure: config.nixstead.host.network.exposure.${exposure};
  selectorsWithSources =
    lib.filter (
      exposure: (selectorFor exposure).sourceNetworks != []
    )
    scopedExposures;
  selectorsWithoutSources =
    lib.filter (
      exposure: (selectorFor exposure).sourceNetworks == []
    )
    scopedExposures;

  interfaceNames = lib.unique (lib.concatMap (
      exposure: (selectorFor exposure).interfaces
    )
    selectorsWithoutSources);
  interfaceRules = lib.genAttrs interfaceNames (interface: {
    allowedTCPPorts = lib.unique (lib.concatMap (
        exposure:
          lib.optionals (lib.elem interface (selectorFor exposure).interfaces) (portsFor "tcp" exposure)
      )
      selectorsWithoutSources);
    allowedUDPPorts = lib.unique (lib.concatMap (
        exposure:
          lib.optionals (lib.elem interface (selectorFor exposure).interfaces) (portsFor "udp" exposure)
      )
      selectorsWithoutSources);
  });

  nftSet = values: lib.concatStringsSep ", " values;
  interfaceMatch = interfaces:
    lib.optionalString (interfaces != []) ''iifname { ${nftSet (map (interface: ''"${interface}"'') interfaces)} } '';
  addressFamilyRules = exposure: protocol: family: let
    selector = selectorFor exposure;
    networks =
      lib.filter (
        network:
          if family == "ip6"
          then lib.hasInfix ":" network
          else !lib.hasInfix ":" network
      )
      selector.sourceNetworks;
    ports = portsFor protocol exposure;
  in
    lib.optionalString (networks != [] && ports != []) ''
      ${interfaceMatch selector.interfaces}${family} saddr { ${nftSet networks} } ${protocol} dport { ${nftSet (map toString ports)} } accept comment "nixstead ${exposure} services"
    '';
  sourceRules = lib.concatMapStrings (exposure:
    lib.concatMapStrings (protocol:
      (addressFamilyRules exposure protocol "ip")
      + (addressFamilyRules exposure protocol "ip6")) ["tcp" "udp"])
  selectorsWithSources;
  forwardAddressFamilyRules = exposure: protocol: family: let
    selector = selectorFor exposure;
    networks =
      lib.filter (
        network:
          if family == "ip6"
          then lib.hasInfix ":" network
          else !lib.hasInfix ":" network
      )
      selector.sourceNetworks;
    ports = publishedPortsFor protocol exposure;
  in
    lib.optionalString (networks != [] && ports != []) ''
      ct status dnat ${interfaceMatch selector.interfaces}${family} saddr { ${nftSet networks} } meta l4proto ${protocol} ct original proto-dst { ${nftSet (map toString ports)} } accept comment "nixstead ${exposure} container services"
    '';
  forwardAllowRules = lib.concatMapStrings (exposure:
    lib.concatMapStrings (protocol:
      (forwardAddressFamilyRules exposure protocol "ip")
      + (forwardAddressFamilyRules exposure protocol "ip6")) ["tcp" "udp"])
  selectorsWithSources;
  forwardDropRules = lib.concatMapStrings (protocol: let
    ports = lib.unique (lib.concatMap (publishedPortsFor protocol) selectorsWithSources);
  in
    lib.optionalString (ports != []) ''
      ct status dnat meta l4proto ${protocol} ct original proto-dst { ${nftSet (map toString ports)} } drop comment "reject container traffic outside nixstead source networks"
    '') ["tcp" "udp"];
  hasSourceRules = sourceRules != "";
  hasForwardSourceRules = forwardAllowRules != "";
in {
  config = lib.mkMerge [
    {
      networking.firewall = {
        allowedTCPPorts = portsFor "tcp" "public";
        allowedUDPPorts = portsFor "udp" "public";
        interfaces = interfaceRules;
      };
    }
    (lib.mkIf hasSourceRules {
      networking.nftables.enable = true;
      networking.firewall.extraInputRules = sourceRules;
    })
    (lib.mkIf hasForwardSourceRules {
      networking.nftables.tables."nixstead-service-exposure" = {
        family = "inet";
        content = ''
          chain forward_source_filter {
            type filter hook forward priority -10; policy accept;
            ${forwardAllowRules}
            ${forwardDropRules}
          }
        '';
      };
    })
    {
      assertions = [
        {
          assertion = !hasSourceRules || config.networking.firewall.backend == "nftables";
          message = "Service source-network exposure rules require the nftables firewall backend.";
        }
      ];
    }
  ];
}
