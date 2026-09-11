{...}: {
  nixstead.services.productivity.nextcloud = {
    enable = true;
    port = 28083;
    paths.dataDir = "/srv/nextcloud-data";
  };
  services.nextcloud.home = "/srv/nextcloud-home";
}
