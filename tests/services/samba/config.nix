{
  mkSystem,
  lib,
  ...
}: let
  base = {
    users.users.fixture = {
      isNormalUser = true;
      uid = 1234;
    };
    nixstead.services.nas.samba = {
      enable = true;
      shares = {
        documents = {
          path = "/srv/documents";
          users = ["fixture"];
        };
        incoming = {
          path = "/srv/incoming";
          users = ["fixture"];
          readOnly = false;
        };
      };
    };
  };
  c = (mkSystem [base]).config;
  exposed = (mkSystem [base {nixstead.host.network.exposure.services.samba = "public";}]).config;
  disabled = (mkSystem [base {nixstead.services.nas.samba.enable = lib.mkForce false;}]).config;
  parent =
    (mkSystem [
      base
      {
        nixstead.services.nas.enable = true;
        nixstead.services.nas.samba.enable = lib.mkForce false;
      }
    ]).config;
  rejects = shares:
    lib.any (a: !a.assertion && lib.hasInfix "explicit list of existing local users" a.message)
    (mkSystem [
      {
        nixstead.services.nas.samba = {
          enable = true;
          inherit shares;
        };
      }
    ]).config.assertions;
in {
  independentOfNasParent = c.services.samba.enable && !c.nixstead.services.nas.enable;
  disabledRemovesNativeServer = !disabled.services.samba.enable;
  parentAllowsChildDisable = !parent.services.samba.enable;
  nativeSharePathsAndIdentity = c.services.samba.settings.documents.path == "/srv/documents" && c.services.samba.settings.documents."valid users" == "fixture";
  explicitReadOnlyPolicy = c.services.samba.settings.documents."read only" == "yes" && c.services.samba.settings.incoming."read only" == "no";
  authenticatedOnly = c.services.samba.settings.global."map to guest" == "Never" && c.services.samba.settings.global."restrict anonymous" == 2 && c.services.samba.settings.documents."guest ok" == "no";
  nativeFirewallDelegatesToRegistry = !c.services.samba.openFirewall && lib.all (p: !(lib.elem p c.networking.firewall.allowedTCPPorts)) [139 445] && lib.all (p: lib.elem p exposed.networking.firewall.allowedTCPPorts) [139 445] && lib.all (p: lib.elem p exposed.networking.firewall.allowedUDPPorts) [137 138];
  noImplicitDirectoryOwnership = !lib.any (rule: lib.hasInfix "/srv/documents" rule || lib.hasInfix "/srv/incoming" rule) c.systemd.tmpfiles.rules;
  missingUsersRejected = rejects {documents.path = "/srv/documents";};
  unknownUserRejected = rejects {
    documents = {
      path = "/srv/documents";
      users = ["absent"];
    };
  };
  reservedShareRejected = rejects {
    global = {
      path = "/srv/documents";
      users = ["root"];
    };
  };
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
}
