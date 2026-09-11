{lib, ...}: {
  users.users.photoowner = {
    isSystemUser = true;
    group = "users";
  };
  users.groups.media = {};
  services.immich = {
    user = "photoowner";
    machine-learning.enable = lib.mkForce false;
    environment.IMMICH_LOG_LEVEL = "warn";
    settings = {
      machineLearning.enabled = false;
      newVersionCheck.enabled = false;
    };
  };
  nixstead.services.media.immich = {
    enable = true;
    paths.mediaLocation = "/srv/photos";
  };
  virtualisation.memorySize = 3072;
}
