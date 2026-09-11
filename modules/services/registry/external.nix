{
  mkService,
  card,
  hostSetup,
  ...
}: {
  pihole = mkService {
    name = "Pi-hole";
    optionPath = ["pihole"];
    defaults = {
      subdomain = "pihole";
      port = 80;
      hostNetwork = "pihole";
    };
    local = false;
    proxy = {
      kind = "pihole";
      target = "service";
      scheme = "http";
    };
    homepage =
      (card "Infrastructure" 30 "Pi-hole" "pi-hole" "DNS / Ad-blocking")
      // {
        hrefSuffix = "/admin/";
        widget = {
          type = "pihole";
          extra.version = 6;
          secrets.key = "piholeApiKey";
        };
      };
    health = {
      external = true;
      protocol = "http";
      suffix = "/admin/";
    };
    setup = hostSetup 710 "Pi-hole integration";
  };

  proxmox = mkService {
    name = "Proxmox";
    optionPath = ["proxmox"];
    defaults = {
      subdomain = "proxmox";
      port = 8006;
      hostNetwork = "proxmox";
    };
    local = false;
    proxy = {
      target = "service";
      scheme = "https";
      websockets = true;
      extraVhostConfig = "proxy_ssl_verify off;\n";
    };
    homepage =
      (card "Infrastructure" 10 "Proxmox" "proxmox" "Hypervisor")
      // {
        widget = {
          type = "proxmox";
          scheme = "https";
          extra.allowInsecure = true;
          secrets = {
            username = "proxmoxUsername";
            password = "proxmoxPassword";
          };
        };
      };
    health = {
      external = true;
      protocol = "https";
    };
    setup = hostSetup 720 "Proxmox integration";
  };

  truenas = mkService {
    name = "TrueNAS";
    optionPath = ["truenas"];
    defaults = {
      subdomain = "nas";
      port = 80;
      hostNetwork = "truenas";
    };
    local = false;
    proxy = {
      target = "service";
      scheme = "http";
      websockets = true;
    };
    homepage =
      (card "Infrastructure" 20 "TrueNAS" "truenas" "Storage")
      // {
        widget = {
          type = "truenas";
          secrets.key = "truenasApiKey";
        };
      };
    health = {
      external = true;
      protocol = "http";
    };
    setup = hostSetup 730 "TrueNAS integration";
  };
}
