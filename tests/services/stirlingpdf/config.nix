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
        nixstead.services.productivity.stirlingpdf = {
          enable = true;
          inherit port;
          domain = "fixture-stirlingpdf.example.test";
        };
      }
    ]).config;
in
  serviceContract {
    id = "stirlingpdf";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.services.stirling-pdf.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.stirlingpdf.port = 70000;}]).config.nixstead.services.productivity.stirlingpdf.port).success;

    nativeListener = cfg.services.stirling-pdf.environment.SERVER_PORT == toString port && cfg.services.stirling-pdf.environment.SERVER_ADDRESS == "127.0.0.1";
    noDatabaseDependency = !cfg.services.postgresql.enable;
  }
