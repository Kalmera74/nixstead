{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixstead.serviceSmokeTests;
  servicesFile = pkgs.writeText "nixstead-services.json" (builtins.toJSON (config.nixstead.services or {}));
  registryFile = pkgs.writeText "nixstead-service-registry.json" (builtins.toJSON config.nixstead.serviceRegistry);
  hostFile = pkgs.writeText "nixstead-host.json" (builtins.toJSON config.nixstead.host);
  smokeTestProgram = pkgs.writeShellApplication {
    name = "nixstead-service-smoke-test";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.iputils
      pkgs.jq
      pkgs.systemd
      pkgs.util-linux
    ];
    text = builtins.readFile ../../scripts/health-homelab.sh;
  };
in {
  options.nixstead.serviceSmokeTests = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run periodic read-only checks for enabled registry services.";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd calendar expression for service smoke tests.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nixstead-service-smoke-test = {
      description = "Smoke-test enabled Nixstead services";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      environment = {
        NIXSTEAD_HOST = config.nixstead.host.configurationName;
        NIXSTEAD_HOST_FILE = hostFile;
        NIXSTEAD_REGISTRY_FILE = registryFile;
        NIXSTEAD_SERVICES_FILE = servicesFile;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${smokeTestProgram}/bin/nixstead-service-smoke-test";
      };
    };

    systemd.timers.nixstead-service-smoke-test = {
      description = "Periodic Nixstead service smoke tests";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "15m";
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
  };
}
