{
  config,
  host,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.media;
  jellyfinNetworkConfig = "${config.services.jellyfin.configDir}/network.xml";
  jellyfinBindAddress = serviceBindAddress "jellyfin";
  configureJellyfinNetwork = pkgs.writeShellScript "configure-jellyfin-network" ''
    set -euo pipefail

    network_config="$1"
    port="$2"
    bind_address="$3"

    # An empty file needs the same initialization as a missing configuration.
    if [[ ! -s "$network_config" ]]; then
      umask 077
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$network_config")"
      ${pkgs.coreutils}/bin/printf '%s\n' \
        '<?xml version="1.0" encoding="utf-8"?>' \
        '<NetworkConfiguration>' \
        '</NetworkConfiguration>' \
        >"$network_config"
    fi

    set_element() {
      local name="$1"
      local value="$2"

      if [[ "$(${pkgs.xmlstarlet}/bin/xmlstarlet select --template --value-of "count(/NetworkConfiguration/$name)" "$network_config")" == "0" ]]; then
        ${pkgs.xmlstarlet}/bin/xmlstarlet edit --inplace \
          --subnode /NetworkConfiguration --type elem --name "$name" --value "$value" \
          "$network_config"
      else
        ${pkgs.xmlstarlet}/bin/xmlstarlet edit --inplace \
          --update "/NetworkConfiguration/$name" --value "$value" \
          "$network_config"
      fi
    }

    set_element InternalHttpPort "$port"
    set_element PublicHttpPort "$port"

    if [[ "$(${pkgs.xmlstarlet}/bin/xmlstarlet select --template --value-of 'count(/NetworkConfiguration/LocalNetworkAddresses)' "$network_config")" == "0" ]]; then
      ${pkgs.xmlstarlet}/bin/xmlstarlet edit --inplace \
        --subnode /NetworkConfiguration --type elem --name LocalNetworkAddresses \
        "$network_config"
    fi

    ${pkgs.xmlstarlet}/bin/xmlstarlet edit --inplace \
      --delete '/NetworkConfiguration/LocalNetworkAddresses/*' \
      "$network_config"

    if [[ "$bind_address" == "127.0.0.1" ]]; then
      ${pkgs.xmlstarlet}/bin/xmlstarlet edit --inplace \
        --subnode /NetworkConfiguration/LocalNetworkAddresses \
        --type elem --name string --value "$bind_address" \
        "$network_config"
    fi
  '';
in {
  config = lib.mkIf cfg.jellyfin.enable {
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        libva-utils
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };

    services.jellyfin.enable = true;
    users.users.jellyfin.extraGroups = ["video" "render" config.nixstead.host.groups.media];

    # Native tmpfiles provisions this directory at boot. Recovery can discard
    # the cache later, so let systemd recreate the default cache at each start.
    systemd.services.jellyfin.serviceConfig = lib.mkIf (config.services.jellyfin.cacheDir == "/var/cache/jellyfin") {
      CacheDirectory = "jellyfin";
      CacheDirectoryMode = "0700";
    };

    systemd.services.jellyfin.preStart = lib.mkAfter ''
      ${configureJellyfinNetwork} \
        ${lib.escapeShellArg jellyfinNetworkConfig} \
        ${toString cfg.jellyfin.port} \
        ${lib.escapeShellArg jellyfinBindAddress}
    '';
  };
}
