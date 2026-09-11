{publicModules}: {
  default = publicModules.default;
  base = [
    publicModules.base
    {
      nixstead.host.user = {
        enable = true;
        name = "api-user";
        uid = 1234;
      };
    }
  ];
  secrets = publicModules.secrets;
  tools = [
    publicModules.tools
    {nixstead.tools.enable = true;}
  ];
  services = [
    publicModules.services
    {nixstead.services.dev.redis.enable = true;}
  ];
  arr = [
    publicModules.arr
    {nixstead.services.arr.radarr.enable = true;}
  ];
  media = [
    publicModules.media
    {nixstead.services.media.jellyfin.enable = true;}
  ];
  dev = [
    publicModules.dev
    {nixstead.services.dev.redis.enable = true;}
  ];
  localai = [
    publicModules.localai
    {nixstead.services.localai.ollama.enable = true;}
  ];
  productivity = [
    publicModules.productivity
    {nixstead.services.productivity.n8n.enable = true;}
  ];
  vaultwarden = [
    publicModules.vaultwarden
    {nixstead.services.vaultwarden.enable = true;}
  ];
  homeassistant = [
    publicModules.homeassistant
    {nixstead.services.homeassistant.enable = true;}
  ];
  authentik = publicModules.authentik;
  syncthing = [
    publicModules.syncthing
    {nixstead.services.syncthing.enable = true;}
  ];
  scrutiny = [
    publicModules.scrutiny
    {nixstead.services.scrutiny.enable = true;}
  ];
  tailscale = [
    publicModules.tailscale
    {nixstead.services.tailscale.enable = true;}
  ];
  wireguard = [
    publicModules.wireguard
    {
      nixstead.services.wireguard = {
        enable = true;
        interfaces.work.configFile = "/run/credentials/work.conf";
      };
    }
  ];
  cifs = [
    publicModules.cifs
    {
      nixstead.services.cifs = {
        enable = true;
        shares.public = {
          source = "//192.0.2.10/public";
          mountPoint = "/mnt/public";
        };
      };
    }
  ];
  nas = [
    publicModules.nas
    {
      nixstead.services.nas = {
        enable = true;
        tankMount = "/srv/fixture-tank";
        disks = {
          data = [
            {
              name = "fixture-data";
              device = "/dev/fixture-data";
              mountPoint = "/mnt/fixture-data";
              fsType = "ext4";
            }
          ];
          parity = [
            {
              device = "/dev/fixture-parity";
              mountPoint = "/mnt/fixture-parity";
              fsType = "ext4";
            }
          ];
        };
      };
    }
  ];
  external = [
    publicModules.external
    {
      nixstead.host.network.pihole = "192.0.2.53";
      nixstead.services.pihole.enable = true;
    }
  ];
  nginx = [
    publicModules.nginx
    {nixstead.services.nginx.enable = true;}
  ];
  homepage = [
    publicModules.homepage
    {nixstead.services.homepage.enable = true;}
  ];
  program-core = [publicModules.default publicModules.program-core];
  program-development = [publicModules.default publicModules.program-development];
  program-hardware = [publicModules.default publicModules.program-hardware];
  program-networking = [publicModules.default publicModules.program-networking];
  program-media = [publicModules.default publicModules.program-media];
  program-backup = [publicModules.default publicModules.program-backup];
  program-zsh = [publicModules.default publicModules.program-zsh];
  program-yazi = [publicModules.default publicModules.program-yazi];
  profile-development = publicModules.profile-development;
  profile-full = publicModules.profile-full;
  profile-media-server = publicModules.profile-media-server;
  profile-minimal = publicModules.profile-minimal;
}
