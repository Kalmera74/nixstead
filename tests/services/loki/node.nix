{...}: {
  nixstead.services.dev.loki = {
    enable = true;
    port = 23100;
    paths.dataDir = "/var/lib/loki-history-fixture";
    journal.enable = false;
  };
  services.loki.configuration = {
    limits_config.retention_period = "24h";
    compactor = {
      retention_enabled = true;
      delete_request_store = "filesystem";
      working_directory = "/var/lib/loki-history-fixture/retention";
    };
  };
  virtualisation.memorySize = 1024;
  virtualisation.diskSize = 4096;
}
