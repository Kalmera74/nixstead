{
  config,
  host,
  lib,
  pkgs,
  secretPath,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
  native = config.services.mongodb;
  mongosh = lib.getExe native.mongoshPackage;
  connection = "--quiet --norc --host 127.0.0.1 --port ${toString cfg.mongodb.port}";
  passwordReader = ''
    const password = require("fs").readFileSync(${builtins.toJSON (toString native.initialRootPasswordFile)}, "utf8").replace(/\n+$/, "");
    if (!password.length) throw new Error("The initial MongoDB password file is empty");
  '';
  bootstrap = pkgs.writeText "nixstead-mongodb-bootstrap.js" ''
    (async () => {
    const admin = db.getSiblingDB("admin");
    ${passwordReader}
    // MongoDB's localhost exception permits only the first account creation.
    // Existing databases stay authenticated even if their marker was lost.
    try {
      await admin.createUser({
        user: "root",
        pwd: password,
        roles: [
          { role: "userAdminAnyDatabase", db: "admin" },
          { role: "dbAdminAnyDatabase", db: "admin" },
          { role: "readWriteAnyDatabase", db: "admin" }
        ]
      });
    } catch (error) {
      if (error.code !== 13) throw error;
      // The initial secret never rotates an existing account. If it no longer
      // matches, refuse initialization without changing users or credentials.
      const authenticated = await admin.auth("root", password);
      if (authenticated !== 1 && authenticated.ok !== 1)
        throw new Error("Existing MongoDB administrator authentication failed");
    }
    })();
  '';
  initialScript = pkgs.writeText "nixstead-mongodb-initial-script.js" ''
    (async () => {
    ${lib.optionalString native.enableAuth ''
      ${passwordReader}
      await db.auth("root", password);
    ''}
    await load(${builtins.toJSON "${native.initialScript}"});
    })();
  '';
  bootstrapConfig = pkgs.writeText "nixstead-mongodb-bootstrap.conf" ''
    net.bindIp: 127.0.0.1
    ${lib.optionalString native.quiet "systemLog.quiet: true"}
    systemLog.destination: syslog
    storage.dbPath: ${native.dbpath}
    ${lib.optionalString (native.replSetName != "") "replication.replSetName: ${native.replSetName}"}
    ${native.extraConfig}
  '';
in {
  config = lib.mkIf cfg.mongodb.enable {
    sops.secrets."devdb/mongodb/rootPassword" = {
      owner = "mongodb";
      restartUnits = ["mongodb.service"];
    };

    services.mongodb = {
      enable = true;
      package = pkgs.mongodb-ce;
      bind_ip = serviceBindAddress "mongodb";
      enableAuth = true;
      initialRootPasswordFile = secretPath "devdb/mongodb/rootPassword";
      extraConfig = ''
        net.port: ${toString config.nixstead.services.dev.mongodb.port}
      '';
    };

    # The pinned native bootstrap assumes port 27017, interpolates its secret
    # into JavaScript, and passes it in argv for initialScript. Keep native
    # mongod/ownership while replacing just those initialization hooks.
    systemd.services.mongodb = {
      preStart = lib.mkForce ''
        set -euo pipefail
        ${lib.optionalString native.enableAuth ''
          if [ ! -e ${lib.escapeShellArg "${native.dbpath}/.auth_setup_complete"} ]; then
            test -s ${lib.escapeShellArg (toString native.initialRootPasswordFile)} || {
              echo "Missing or empty initial MongoDB password file; database initialization refused." >&2
              exit 1
            }
          fi
        ''}
        if [ ! -d ${lib.escapeShellArg native.dbpath} ]; then
          install -d -m 0700 -o ${lib.escapeShellArg native.user} ${lib.escapeShellArg native.dbpath}
        fi
        rm -f ${lib.escapeShellArg "${native.dbpath}/mongod.lock"}
        if [ ! -e ${lib.escapeShellArg "${native.dbpath}/storage.bson"} ]; then
          touch ${lib.escapeShellArg "${native.dbpath}/.first_startup"}
        fi
        if [ ! -e ${lib.escapeShellArg native.pidFile} ]; then
          install -D -o ${lib.escapeShellArg native.user} /dev/null ${lib.escapeShellArg native.pidFile}
        fi
        ${lib.optionalString native.enableAuth ''
          if [ ! -e ${lib.escapeShellArg "${native.dbpath}/.auth_setup_complete"} ]; then
            cleanup() { systemctl stop mongodb-for-setup.service >/dev/null 2>&1 || true; }
            trap cleanup EXIT
            systemd-run --collect --unit=mongodb-for-setup --uid=${lib.escapeShellArg native.user} \
              ${native.package}/bin/mongod --auth --config ${bootstrapConfig}
            deadline=$((SECONDS + 60))
            until (exec 3<>/dev/tcp/127.0.0.1/${toString cfg.mongodb.port}) 2>/dev/null; do
              if [ "$SECONDS" -ge "$deadline" ] || ! systemctl is-active --quiet mongodb-for-setup.service; then
                echo "MongoDB initialization listener did not become ready." >&2
                exit 1
              fi
              sleep 0.2
            done
            ${mongosh} ${connection} --file ${bootstrap}
            touch ${lib.escapeShellArg "${native.dbpath}/.auth_setup_complete"}
            cleanup
            trap - EXIT
          fi
        ''}
      '';
      postStart = lib.mkForce ''
        if [ -e ${lib.escapeShellArg "${native.dbpath}/.first_startup"} ]; then
          ${lib.optionalString (native.initialScript != null) ''
          ${mongosh} ${connection} admin --file ${initialScript}
        ''}
          rm -f ${lib.escapeShellArg "${native.dbpath}/.first_startup"}
        fi
      '';
    };
  };
}
