{
  config,
  host,
  lib,
  secretPlaceholder,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
in {
  config = lib.mkIf cfg.rabbitmq.enable {
    sops.secrets = {
      "devdb/rabbitmq/rootUser" = {};
      "devdb/rabbitmq/rootPassword" = {};
    };

    sops.templates."rabbitmq-admin.env" = {
      owner = "rabbitmq";
      content = ''
        RABBITMQ_ROOT_USER=${secretPlaceholder "devdb/rabbitmq/rootUser"}
        RABBITMQ_ROOT_PASSWORD=${secretPlaceholder "devdb/rabbitmq/rootPassword"}
      '';
      restartUnits = ["rabbitmq.service"];
    };

    services.rabbitmq = {
      enable = true;
      listenAddress = serviceBindAddress "rabbitmq";
      port = config.nixstead.services.dev.rabbitmq.port;
    };

    systemd.services.rabbitmq.unitConfig.RequiresMountsFor = [config.services.rabbitmq.dataDir];
    systemd.services.rabbitmq.serviceConfig.EnvironmentFile = [config.sops.templates."rabbitmq-admin.env".path];
    systemd.services.rabbitmq.postStart = lib.mkAfter ''
      rabbitmq_root_user="$RABBITMQ_ROOT_USER"
      rabbitmq_root_password="$RABBITMQ_ROOT_PASSWORD"

      ${config.services.rabbitmq.package}/sbin/rabbitmqctl await_startup

      if [ -n "$rabbitmq_root_password" ]; then
        # Read the password through stdin instead of exposing it in CLI argv.
        if ! printf '%s\n' "$rabbitmq_root_password" | ${config.services.rabbitmq.package}/sbin/rabbitmqctl change_password "$rabbitmq_root_user"; then
          printf '%s\n' "$rabbitmq_root_password" | ${config.services.rabbitmq.package}/sbin/rabbitmqctl add_user "$rabbitmq_root_user"
        fi
        ${config.services.rabbitmq.package}/sbin/rabbitmqctl set_user_tags "$rabbitmq_root_user" administrator
        ${config.services.rabbitmq.package}/sbin/rabbitmqctl set_permissions -p / "$rabbitmq_root_user" '.*' '.*' '.*'
      fi

      if [ -n "$rabbitmq_root_password" ] && [ "$rabbitmq_root_user" != "guest" ]; then
        ${config.services.rabbitmq.package}/sbin/rabbitmqctl delete_user guest || true
      fi
    '';
  };
}
