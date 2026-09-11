{
  config,
  hardenContainer,
  lib,
  pkgs,
  secretPlaceholder,
  servicePublishAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity;
  dataDir = config.nixstead.services.productivity.seafile.paths.dataDir;
  seahubSettingsFile = "${dataDir}/data/seafile/conf/seahub_settings.py";
  configureSeafileHttps = pkgs.writeShellScript "configure-seafile-https" ''
    set -euo pipefail

    conf_file="$1"
    changed=false

    set_setting() {
      local name="$1"
      local value="$2"
      local expected="''${name} = ''${value}"

      if ${pkgs.gnugrep}/bin/grep -Fqx "$expected" "$conf_file"; then
        return
      fi

      if ${pkgs.gnugrep}/bin/grep -qE "^''${name}[[:space:]]*=" "$conf_file"; then
        ${pkgs.gnused}/bin/sed -i -E "s|^''${name}[[:space:]]*=.*|$expected|" "$conf_file"
      else
        ${pkgs.coreutils}/bin/printf '\n%s\n' "$expected" >> "$conf_file"
      fi
      changed=true
    }

    set_setting SERVICE_URL '"https://${config.nixstead.services.productivity.seafile.domain}"'
    set_setting FILE_SERVER_ROOT '"https://${config.nixstead.services.productivity.seafile.domain}/seafhttp"'
    set_setting CSRF_TRUSTED_ORIGINS '["https://${config.nixstead.services.productivity.seafile.domain}"]'
    set_setting USE_X_FORWARDED_HOST 'True'
    set_setting SECURE_PROXY_SSL_HEADER '("HTTP_X_FORWARDED_PROTO", "https")'

    ${pkgs.coreutils}/bin/printf '%s\n' "$changed"
  '';
in {
  config = lib.mkIf cfg.seafile.enable {
    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker.enable = true;

    sops.secrets = {
      "seafile/adminEmail" = {};
      "seafile/adminPassword" = {};
      "seafile/dbRootPassword" = {};
    };

    sops.templates = {
      "seafile-db.env" = {
        content = ''
          MYSQL_ROOT_PASSWORD=${secretPlaceholder "seafile/dbRootPassword"}
        '';
        restartUnits = ["docker-seafile-db.service"];
      };
      "seafile.env" = {
        content = ''
          DB_ROOT_PASSWD=${secretPlaceholder "seafile/dbRootPassword"}
          SEAFILE_ADMIN_EMAIL=${secretPlaceholder "seafile/adminEmail"}
          SEAFILE_ADMIN_PASSWORD=${secretPlaceholder "seafile/adminPassword"}
        '';
        restartUnits = ["docker-seafile.service"];
      };
    };

    system.activationScripts.seafile-data-dirs = {
      deps = ["users" "groups"];
      text = ''
        # Native bootstrap stores database credentials and signing material
        # below this tree. Keep the root-owned container state private on host.
        install -d -m 0700 -o root -g root ${lib.escapeShellArg dataDir}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg "${dataDir}/db"}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg "${dataDir}/data"}
      '';
    };

    system.activationScripts.seafile-force-https = {
      deps = ["seafile-data-dirs"];
      text = ''
        conf_file=${lib.escapeShellArg seahubSettingsFile}
        if [ -f "$conf_file" ]; then
          ${configureSeafileHttps} "$conf_file" >/dev/null
        fi
      '';
    };

    virtualisation.oci-containers.containers = {
      seafile-db =
        hardenContainer {
          memory = "2g";
          cpus = "1";
          healthCommand = "healthcheck.sh --connect --innodb_initialized";
          healthStartPeriod = "30s";
          readOnlyRootFilesystem = true;
          tmpfs = [
            "/run/mysqld:rw,noexec,nosuid,size=64m"
            "/tmp:rw,noexec,nosuid,size=64m"
          ];
        }
        // {
          image = cfg.seafile.images.database;
          autoStart = true;
          networks = ["seafile-net"];
          volumes = ["${dataDir}/db:/var/lib/mysql"];
          environmentFiles = [config.sops.templates."seafile-db.env".path];
          environment = {
            MYSQL_LOG_CONSOLE = "true";
            MARIADB_AUTO_UPGRADE = "1";
          };
        };

      seafile-memcached =
        hardenContainer {
          memory = "256m";
          cpus = "0.5";
          pidsLimit = 64;
          healthCommand = "bash -ec 'exec 3<>/dev/tcp/127.0.0.1/11211; printf \"version\\r\\n\" >&3; grep -q VERSION <&3'";
          readOnlyRootFilesystem = true;
          tmpfs = ["/tmp:rw,noexec,nosuid,size=16m"];
          # The pinned bootstrap writes memcached:11211 into Seahub settings.
          extraOptions = ["--network-alias=memcached"];
        }
        // {
          image = cfg.seafile.images.memcached;
          autoStart = true;
          networks = ["seafile-net"];
        };

      seafile =
        hardenContainer {
          memory = "4g";
          cpus = "2";
          pidsLimit = 1024;
          healthCommand = "curl -fsS http://127.0.0.1/api2/ping/ >/dev/null";
          healthStartPeriod = "300s";
        }
        // {
          image = cfg.seafile.images.application;
          autoStart = true;
          networks = ["seafile-net"];
          dependsOn = [
            "seafile-db"
            "seafile-memcached"
          ];
          ports = ["${servicePublishAddress "seafile"}:${toString config.nixstead.services.productivity.seafile.port}:80"];
          volumes = ["${dataDir}/data:/shared"];
          environmentFiles = [config.sops.templates."seafile.env".path];
          environment = {
            DB_HOST = "seafile-db";
            FORCE_HTTPS_IN_CONF = "true";
            TIME_ZONE = config.nixstead.host.locale.timeZone;
            SEAFILE_SERVER_LETSENCRYPT = "false";
            SEAFILE_SERVER_HOSTNAME = config.nixstead.services.productivity.seafile.domain;
          };
        };
    };

    systemd.services.docker-seafile.preStart = lib.mkAfter ''
      ${pkgs.python3}/bin/python3 ${./seafile-database-user.py} \
        ${lib.escapeShellArg "${dataDir}/data/seafile/conf/seafile.conf"} ${pkgs.docker}/bin/docker
    '';

    systemd.services.docker-seafile.postStart = lib.mkAfter ''
      seahub_ready=false
      seahub_ready_deadline=$((SECONDS + 300))
      while [ "$SECONDS" -lt "$seahub_ready_deadline" ]; do
        # A gunicorn process can exist while native bootstrap is still running
        # seahub.sh. Its transient admin file disappears only after that script
        # finishes; wait for both completion and actual HTTP readiness before
        # restarting Seahub to apply managed HTTPS settings.
        if [ ! -e ${lib.escapeShellArg "${dataDir}/data/seafile/conf/admin.txt"} ] && \
          ${pkgs.coreutils}/bin/timeout 5 ${pkgs.docker}/bin/docker exec seafile \
            curl --max-time 2 -fsS http://127.0.0.1/api2/ping/ >/dev/null 2>&1; then
          seahub_ready=true
          break
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done

      if [ "$seahub_ready" != true ]; then
        echo "Seahub did not become ready within 300 seconds" >&2
        exit 1
      fi

      conf_file=${lib.escapeShellArg seahubSettingsFile}
      if [ ! -f "$conf_file" ]; then
        echo "Seahub settings file was not created: $conf_file" >&2
        exit 1
      fi

      settings_changed="$(${configureSeafileHttps} "$conf_file")"
      if [ "$settings_changed" = true ]; then
        # The pinned native stop helper waits only one second for gunicorn.
        # Give graceful termination a bounded retry window before starting a
        # fresh process with the new configuration; never overlap processes.
        seahub_stopped=false
        seahub_stop_deadline=$((SECONDS + 30))
        while [ "$SECONDS" -lt "$seahub_stop_deadline" ]; do
          if ${pkgs.coreutils}/bin/timeout 5 ${pkgs.docker}/bin/docker exec seafile \
            /opt/seafile/seafile-server-latest/seahub.sh stop >/dev/null 2>&1; then
            seahub_stopped=true
            break
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        if [ "$seahub_stopped" != true ]; then
          echo "Seahub did not stop to apply managed HTTPS settings" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/timeout 60 ${pkgs.docker}/bin/docker exec seafile \
          /opt/seafile/seafile-server-latest/seahub.sh start 8000
      fi
    '';
  };
}
