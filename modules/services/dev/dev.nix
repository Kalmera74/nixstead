{
  config,
  lib,
  ociImagesOption,
  optionalRuntimePathOption,
  runtimePathOption,
  serviceOptionFromRegistry,
  serviceRegistry,
  ...
}: let
  cfg = config.nixstead.services.dev;
  exporterOption = {
    description,
    port,
    extraOptions ? {},
  }:
    lib.mkOption {
      type = lib.types.submodule {
        options =
          {
            enable = lib.mkEnableOption description;
            listenAddress = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Address on which the exporter listens.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = port;
              description = "TCP port on which the exporter exposes Prometheus metrics.";
            };
            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to allow remote connections to the exporter through the host firewall.";
            };
          }
          // extraOptions;
      };
      default = {};
      inherit description;
    };
in {
  options.nixstead.services.dev = {
    enable = lib.mkEnableOption "Development stack";
    grafana = serviceOptionFromRegistry "grafana" {
      enable = cfg.enable;
      pathOptions.dataDir = optionalRuntimePathOption "Optional absolute Grafana state directory; the native NixOS default is used when unset.";
      extraOptions.provisioning = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "declarative Grafana data sources and dashboards";
            prometheus = {
              enable = lib.mkEnableOption "the provisioned Prometheus data source";
              url = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "http://prometheus.internal:9090";
                description = "Prometheus URL used by Grafana; null selects the local configured Prometheus service.";
              };
            };
            loki = {
              enable = lib.mkEnableOption "the provisioned Loki data source";
              url = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "http://loki.internal:3100";
                description = "Loki URL used by Grafana; null selects the local configured Loki service.";
              };
            };
            serviceUsageDashboard.enable = lib.mkEnableOption "the editable service usage and resource dashboard";
            arrDashboard.enable = lib.mkEnableOption "the editable ARR application monitoring dashboard";
            dashboardPaths = lib.mkOption {
              type = lib.types.listOf lib.types.path;
              default = [];
              example = [lib.literalExpression "./dashboards"];
              description = "Additional files or directories containing Grafana dashboards to provision.";
            };
            extraDataSources = lib.mkOption {
              type = lib.types.listOf lib.types.attrs;
              default = [];
              description = "Additional Grafana data source definitions appended to the built-in data sources.";
            };
          };
        };
        default = {};
        description = "Optional declarative Grafana integration. Dashboards created directly in the UI remain supported.";
      };
    };
    prometheus = serviceOptionFromRegistry "prometheus" {
      enable = cfg.enable;
      pathOptions.stateDir = optionalRuntimePathOption "Optional absolute Prometheus state directory below /var/lib; the native NixOS default is used when unset.";
      extraOptions = {
        scrapeInterval = lib.mkOption {
          type = lib.types.str;
          default = "15s";
          description = "Default Prometheus scrape interval.";
        };
        extraScrapeConfigs = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [];
          description = "Additional Prometheus scrape configurations appended to the generated local jobs.";
        };
        exporters = {
          node = exporterOption {
            description = "the Prometheus node exporter for host resource metrics";
            port = 9100;
            extraOptions = {
              enabledCollectors = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = "Additional node exporter collectors to enable.";
              };
              disabledCollectors = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = "Default node exporter collectors to disable.";
              };
            };
          };
          systemd = exporterOption {
            description = "the Prometheus systemd exporter for unit state and resource metrics";
            port = 9558;
            extraOptions.extraFlags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "--systemd.collector.enable-restart-count"
                "--systemd.collector.enable-ip-accounting"
              ];
              description = "Additional systemd exporter command-line flags.";
            };
          };
          nginxLog = exporterOption {
            description = "the Prometheus NGINX log exporter for per-service request metrics";
            port = 9117;
            extraOptions = {
              configureNginx = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to configure the privacy-conscious NGINX access log consumed by the exporter.";
              };
              accessLogDirectory = lib.mkOption {
                type = lib.types.path;
                default = "/var/log/nginx";
                description = "Absolute directory containing the per-service NGINX access logs consumed by the exporter.";
              };
              histogramBuckets = lib.mkOption {
                type = lib.types.listOf lib.types.number;
                default = [0.005 0.01 0.025 0.05 0.1 0.25 0.5 1 2.5 5 10 30 60];
                description = "Response-time histogram buckets in seconds.";
              };
            };
          };
          cadvisor = exporterOption {
            description = "cAdvisor for detailed systemd cgroup and container resource metrics";
            port = 9280;
            extraOptions.extraOptions = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Additional cAdvisor command-line options.";
            };
          };
        };
      };
    };
    loki = serviceOptionFromRegistry "loki" {
      enable = cfg.enable;
      pathOptions.dataDir = optionalRuntimePathOption "Optional absolute Loki state directory; the native NixOS default is used when unset.";
      extraOptions.journal = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "shipping the systemd journal to Loki with Grafana Alloy";
            endpoint = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "http://loki.internal:3100/loki/api/v1/push";
              description = "Loki push endpoint; null selects the local configured Loki service.";
            };
            maxAge = lib.mkOption {
              type = lib.types.str;
              default = "12h";
              description = "Maximum age of journal entries read when Alloy starts.";
            };
            extraConfig = lib.mkOption {
              type = lib.types.lines;
              default = "";
              description = "Additional Grafana Alloy configuration appended to the generated journal pipeline.";
            };
          };
        };
        default = {};
        description = "Optional systemd journal pipeline from Grafana Alloy to Loki.";
      };
    };
    redis = serviceOptionFromRegistry "redis" {enable = cfg.enable;};
    rabbitmq = serviceOptionFromRegistry "rabbitmq" {enable = cfg.enable;};
    postgresql = serviceOptionFromRegistry "postgresql" {enable = cfg.enable;};
    mongodb = serviceOptionFromRegistry "mongodb" {enable = cfg.enable;};
    forgejo = serviceOptionFromRegistry "forgejo" {
      enable = cfg.enable;
      pathOptions = {
        stateDir = optionalRuntimePathOption "Optional absolute Forgejo state directory; the native NixOS default is used when unset.";
        repositoryDir = optionalRuntimePathOption "Optional absolute Forgejo repository directory; the native NixOS default is used when unset.";
      };
    };
    gitea = serviceOptionFromRegistry "gitea" {
      enable = cfg.enable;
      pathOptions.stateDir = optionalRuntimePathOption "Optional absolute Gitea state directory; the native NixOS default is used when unset.";
    };
    pgadmin = serviceOptionFromRegistry "pgadmin" {
      enable = cfg.enable;
      extraOptions.initialEmail = lib.mkOption {
        type = lib.types.str;
        default = "admin@pgadmin.local";
        description = "Initial pgAdmin account email; this identifier is not treated as a secret.";
      };
    };
    seaweedfs = serviceOptionFromRegistry "seaweedfs" {
      enable = cfg.enable;
      pathOptions.dataDir = runtimePathOption "/var/lib/seaweedfs" "Absolute directory containing SeaweedFS master, volume, and filer state.";
      extraOptions.masterPort = lib.mkOption {
        type = lib.types.port;
        default = serviceRegistry.seaweedfs.defaults.masterPort;
        description = "SeaweedFS master API port.";
      };
    };
    uptimekuma = serviceOptionFromRegistry "uptimekuma" {
      enable = cfg.enable;
      pathOptions.dataDir = runtimePathOption "/var/lib/uptimekuma" "Absolute directory containing Uptime Kuma state.";
      extraOptions.images =
        ociImagesOption
        (lib.mapAttrs (_: image: image.default) serviceRegistry.uptimekuma.ociImages)
        "Digest-pinned OCI images used by Uptime Kuma.";
    };
    ntfy = serviceOptionFromRegistry "ntfy" {
      enable = cfg.enable;
      pathOptions.dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/ntfy-sh";
        readOnly = true;
        description = "Native ntfy state directory containing messages, attachments, and bootstrap credentials.";
      };
      extraOptions.adminUsername = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9._-]+";
        default = "admin";
        description = "Declaratively provisioned ntfy administrator username.";
      };
      extraOptions.adminPasswordFile = optionalRuntimePathOption "Optional absolute file containing the ntfy administrator password, such as a sops-nix secret path; a password is generated when unset.";
    };
  };

  imports = [
    ./grafana.nix
    ./prometheus.nix
    ./loki.nix
    ./alloy.nix
    ./redis.nix
    ./rabbitmq.nix
    ./postgresql.nix
    ./mongodb.nix
    ./forgejo.nix
    ./gitea.nix
    ./pgadmin.nix
    ./seaweedfs.nix
    ./uptimekuma.nix
    ./ntfy.nix
  ];
}
