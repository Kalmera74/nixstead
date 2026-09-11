{...}: {
  nixstead.services.dev.prometheus = {
    enable = true;
    port = 29091;
    paths.stateDir = "/var/lib/prometheus-history-fixture";
    scrapeInterval = "1s";
    exporters.node = {
      enable = true;
      port = 29100;
      enabledCollectors = ["textfile"];
    };
  };
  services.prometheus = {
    retentionTime = "24h";
    globalConfig.scrape_timeout = "1s";
    exporters.node.extraFlags = ["--collector.textfile.directory=/var/lib/prometheus-measurement-fixture"];
  };
  systemd.tmpfiles.rules = ["d /var/lib/prometheus-measurement-fixture 0755 root root -"];
  virtualisation.memorySize = 768;
  virtualisation.diskSize = 4096;
}
