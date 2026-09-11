{
  config,
  pkgs,
  ...
}: let
  backupRoot = "${config.nixstead.services.cifs.shares.backups.mountPoint}/test-node";
in {
  nixstead.services.cifs.shares.backups = {
    source = "//192.0.2.10/backups";
    mountPoint = "/mnt/private-backups";
    options = [
      "uid=0"
      "gid=0"
      "forceuid"
      "forcegid"
      "mfsymlinks"
      "file_mode=0600"
      "dir_mode=0700"
    ];
  };

  sops.secrets."borg/passphrase".mode = "0400";
  sops.templates."borg-backup.env" = {
    mode = "0400";
    content = ''
      BORG_PASSCOMMAND="${pkgs.coreutils}/bin/cat ${config.sops.secrets."borg/passphrase".path}"
    '';
  };

  nixstead.backups = {
    enable = true;
    repository = "${backupRoot}/borg-service-data";
    stateDirectory = backupRoot;
    environmentFile = config.sops.templates."borg-backup.env".path;
    schedule = "Sun 03:00";
    verifySchedule = "Mon 03:00";
    keepLast = 2;
  };

  nixstead.services.vaultwarden.backup = {
    user = "root";
    group = "root";
    schedule = "Sun 02:00";
  };
}
