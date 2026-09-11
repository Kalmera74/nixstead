{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.services.dev;
  journalCfg = cfg.loki.journal;
  endpoint =
    if journalCfg.endpoint != null
    then journalCfg.endpoint
    else "http://127.0.0.1:${toString cfg.loki.port}/loki/api/v1/push";
in {
  config = lib.mkIf journalCfg.enable {
    services.alloy = {
      enable = true;
      extraFlags = ["--disable-reporting"];
    };

    environment.etc."alloy/nixstead-journal.alloy".text = ''
      loki.source.journal "system" {
        max_age       = "${journalCfg.maxAge}"
        relabel_rules = loki.relabel.system.rules
        forward_to    = [loki.write.local.receiver]
        labels = {
          host = "${config.nixstead.host.hostName}",
          job  = "systemd-journal",
        }
      }

      loki.relabel "system" {
        // Journal metadata is internal and must be renamed at the source.
        forward_to = []

        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }

        rule {
          source_labels = ["__journal_priority_keyword"]
          target_label  = "level"
        }

        rule {
          source_labels = ["__journal_syslog_identifier"]
          target_label  = "syslog_identifier"
        }
      }

      loki.write "local" {
        endpoint {
          url = "${endpoint}"
        }
      }

      ${journalCfg.extraConfig}
    '';
  };
}
