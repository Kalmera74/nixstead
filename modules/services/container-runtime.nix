{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) attrValues concatLists filter filterAttrs hasPrefix head listToAttrs mapAttrs mapAttrs' nameValuePair optional splitString unique;

  hardenContainer = {
    memory,
    cpus,
    pidsLimit ? 256,
    readOnlyRootFilesystem ? false,
    tmpfs ? [],
    healthCommand,
    healthInterval ? "30s",
    healthTimeout ? "10s",
    healthRetries ? 3,
    healthStartPeriod ? "10s",
    dropNetRaw ? true,
    extraOptions ? [],
  }: {
    pull = "missing";
    capabilities =
      {
        AUDIT_WRITE = false;
        MKNOD = false;
      }
      // lib.optionalAttrs dropNetRaw {NET_RAW = false;};
    extraOptions =
      [
        "--memory=${memory}"
        "--cpus=${cpus}"
        "--pids-limit=${toString pidsLimit}"
        "--security-opt=no-new-privileges=true"
        "--health-cmd=${healthCommand}"
        "--health-interval=${healthInterval}"
        "--health-timeout=${healthTimeout}"
        "--health-retries=${toString healthRetries}"
        "--health-start-period=${healthStartPeriod}"
      ]
      ++ optional readOnlyRootFilesystem "--read-only"
      ++ map (mount: "--tmpfs=${mount}") tmpfs
      ++ extraOptions;
  };

  containers = config.virtualisation.oci-containers.containers;
  builtInNetworks = [
    "bridge"
    "host"
    "none"
  ];
  customNetworksByContainer =
    mapAttrs (
      _: container: filter (network: !(lib.elem network builtInNetworks)) container.networks
    )
    containers;
  containersWithCustomNetworks = filterAttrs (_: networks: networks != []) customNetworksByContainer;
  customNetworks = unique (concatLists (attrValues customNetworksByContainer));
  networkUnitName = network: "docker-network-${builtins.substring 0 16 (builtins.hashString "sha256" network)}";

  bindMountsByContainer =
    mapAttrs (
      _: container:
        filter (path: hasPrefix "/" path) (map (volume: head (splitString ":" volume)) container.volumes)
    )
    containers;
  containersWithBindMounts = filterAttrs (_: paths: paths != []) bindMountsByContainer;

  networkServices = listToAttrs (map (network:
    nameValuePair (networkUnitName network) {
      description = "Create the ${network} Docker network";
      requires = ["docker.service"];
      after = ["docker.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if ! ${pkgs.docker}/bin/docker network inspect ${lib.escapeShellArg network} >/dev/null 2>&1; then
          ${pkgs.docker}/bin/docker network create ${lib.escapeShellArg network} >/dev/null
        fi
      '';
    })
  customNetworks);

  containerNetworkDependencies = mapAttrs' (containerName: networks: let
    units = map (network: "${networkUnitName network}.service") networks;
    serviceName = containers.${containerName}.serviceName;
  in
    nameValuePair serviceName {
      after = units;
      requires = units;
    })
  containersWithCustomNetworks;

  containerMountDependencies = mapAttrs' (containerName: paths:
    nameValuePair containers.${containerName}.serviceName {
      unitConfig.RequiresMountsFor = paths;
    })
  containersWithBindMounts;
in {
  config = lib.mkMerge [
    {_module.args = {inherit hardenContainer;};}
    (lib.mkIf (
        config.virtualisation.oci-containers.backend
        == "docker"
        && customNetworks != []
      ) {
        systemd.services = lib.mkMerge [networkServices containerNetworkDependencies];
      })
    {systemd.services = containerMountDependencies;}
  ];
}
