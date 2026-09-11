{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  c =
    (mkSystem [
      {
        nixstead.services.scrutiny = {
          enable = true;
          port = 28192;
          influxdbPort = 28086;
        };
      }
    ]).config;
  disabled = (mkSystem []).config;
  rejectsPath = name: !(builtins.tryEval (mkSystem [{nixstead.services.scrutiny.paths.${name} = "/srv/unsupported";}]).config.nixstead.services.scrutiny.paths.${name}).success;
in
  (serviceContract {
    id = "scrutiny";
    port = 28192;
    nativeEnabled = c: c.services.scrutiny.enable;
  })
  // {
    nativeListener = c.services.scrutiny.settings.web.listen.host == "127.0.0.1" && c.services.scrutiny.settings.web.listen.port == 28192;
    influxDependencyAndEndpoint = c.services.influxdb2.enable && c.services.influxdb2.settings."http-bind-address" == "127.0.0.1:28086" && c.services.scrutiny.settings.web.influxdb.port == 28086;
    disabledRemovesDatabase = !disabled.services.influxdb2.enable;
    collectorIdentityAndSchedule = c.services.scrutiny.collector.enable && c.services.scrutiny.collector.schedule == "daily" && c.services.scrutiny.collector.settings.host.id == c.nixstead.host.hostName;
    fixedPathsRejectOverride = rejectsPath "dataDir" && rejectsPath "influxdbDir";
    combinedStateArchive = c.nixstead.serviceRegistry.scrutiny.backup.paths == ["/var/lib/scrutiny" "/var/lib/influxdb2"] && c.nixstead.serviceRegistry.scrutiny.backup.units == ["scrutiny.service" "influxdb2.service"];
    databaseNotExposed = !(lib.elem 28086 c.networking.firewall.allowedTCPPorts);
  }
