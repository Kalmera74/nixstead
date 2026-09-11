{pkgs, ...}: {
  nixstead.services.productivity.searxng = {
    enable = true;
    port = 28191;
    domain = "search.example.test";
  };

  services.searx.settings = {
    use_default_settings.engines.keep_only = [];
    search.formats = ["html" "json"];
    engines = [
      {
        name = "fixture";
        engine = "json_engine";
        shortcut = "fx";
        categories = ["general"];
        paging = false;
        search_url = "http://127.0.0.2:18082/search?q={query}";
        results_query = "results";
        url_query = "url";
        title_query = "title";
        content_query = "snippet";
        # SearXNG disables plain HTTP transports by default. The deterministic
        # engine fixture is loopback-only, so opt in for this engine alone.
        enable_http = true;
        disabled = false;
      }
    ];
  };
  # Keep native local health/application probes outside the public limiter while
  # still exercising its real bot policy through a trusted forwarded address.
  services.searx.limiterSettings.botdetection.ip_lists.pass_ip = ["127.0.0.0/8"];

  systemd.services.searxng-engine-fixture = {
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 /etc/searxng-engine-fixture.py serve";
      StateDirectory = "searxng-engine-fixture";
    };
  };

  environment.etc."searxng-engine-fixture.py".source = ./probe.py;
  environment.systemPackages = [pkgs.python3];
  virtualisation.memorySize = 1536;
  virtualisation.diskSize = 4096;
}
