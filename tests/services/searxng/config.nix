{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  port = 23456;
  cfg =
    (mkSystem [
      {
        nixstead.services.productivity.searxng = {
          enable = true;
          inherit port;
          domain = "fixture-searxng.example.test";
        };
      }
    ]).config;
in
  serviceContract {
    id = "searxng";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.services.searx.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.searxng.port = 70000;}]).config.nixstead.services.productivity.searxng.port).success;

    nativeListener = cfg.services.searx.settings.server.port == port && cfg.services.searx.settings.server.bind_address == "127.0.0.1";
    persistedSecretEnvironment = cfg.services.searx.environmentFile == "/var/lib/searxng/environment";
    runtimeSecretReference = cfg.services.searx.settings.server.secret_key == "$SEARX_SECRET_KEY";
    limiterEnabled = cfg.services.searx.settings.server.limiter;
    cacheDependency = cfg.services.redis.servers.searx.enable && lib.elem "redis-searx.service" cfg.systemd.services.searx.requires;
    secretBootstrapOrdering = lib.elem "searxng-bootstrap-secret.service" cfg.systemd.services.searx-init.requires;
    backupIncludesSecret = cfg.nixstead.serviceRegistry.searxng.backup.paths == ["/var/lib/searxng"];
    fixedPathRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.searxng.paths.dataDir = "/srv/search";}]).config.nixstead.services.productivity.searxng.paths.dataDir).success;
  }
