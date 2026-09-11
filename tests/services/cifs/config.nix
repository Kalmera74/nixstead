{
  mkSystem,
  lib,
  ...
}: let
  base = {
    nixstead.services.cifs = {
      enable = true;
      credentialsFile = "/run/credentials/smb";
      uid = 1234;
      gid = "media";
      shares = {
        fixture = {
          source = "//192.0.2.10/fixture";
          mountPoint = "/mnt/fixture";
          options = ["ro"];
        };
        absent = null;
      };
    };
  };
  c = (mkSystem [base]).config;
  disabled = (mkSystem [base {nixstead.services.cifs.enable = lib.mkForce false;}]).config;
  empty = (mkSystem [{nixstead.services.cifs.enable = true;}]).config;
  duplicate =
    (mkSystem [
      base
      {
        nixstead.services.cifs.shares.duplicate = {
          source = "//192.0.2.10/other";
          mountPoint = "/mnt/fixture";
        };
      }
    ]).config;
in {
  nativeMount = c.fileSystems."/mnt/fixture".fsType == "cifs" && c.fileSystems."/mnt/fixture".device == "//192.0.2.10/fixture";
  disabledRemovesMountAndCredentials = !(disabled.fileSystems ? "/mnt/fixture") && !(disabled.sops.templates ? "cifs-credentials") && !(disabled.sops.secrets ? "cifs/password");
  explicitMountOptions = lib.all (option: lib.elem option c.fileSystems."/mnt/fixture".options) ["credentials=/run/credentials/smb" "uid=1234" "gid=media" "ro" "x-systemd.automount" "noauto" "noserverino"];
  credentialsRuntimeAndPrivate = c.sops.templates."cifs-credentials".path == "/run/credentials/smb" && c.sops.templates."cifs-credentials".mode == "0400" && lib.hasInfix c.sops.placeholder."cifs/password" c.sops.templates."cifs-credentials".content;
  emptySharesRejected = lib.any (a: !a.assertion && lib.hasInfix "requires at least one share" a.message) empty.assertions;
  duplicateMountsRejected = lib.any (a: !a.assertion && lib.hasInfix "unique mountPoint" a.message) duplicate.assertions;
  noLocalServer = !c.services.samba.enable;
  noIndependentRemoteDataArchive = c.nixstead.serviceRegistry.cifs.backup == null;
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
}
