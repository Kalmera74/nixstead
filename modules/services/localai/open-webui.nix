{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.localai;
  ollamaUrl =
    if cfg.openwebui.ollamaUrl != null
    then cfg.openwebui.ollamaUrl
    else if cfg.ollama.enable
    then "http://127.0.0.1:${toString cfg.ollama.port}"
    else null;
  validOllamaUrl =
    ollamaUrl
    != null
    && (lib.hasPrefix "http://" ollamaUrl || lib.hasPrefix "https://" ollamaUrl);
in {
  config = lib.mkIf cfg.openwebui.enable {
    assertions = [
      {
        assertion = validOllamaUrl;
        message = "Open WebUI requires nixstead.services.localai.ollama.enable or an explicit nixstead.services.localai.openwebui.ollamaUrl.";
      }
    ];

    services.open-webui = {
      enable = true;
      host = serviceBindAddress "openwebui";
      port = config.nixstead.services.localai.openwebui.port;
      inherit (cfg.openwebui) environmentFile;
      environment = {
        OLLAMA_BASE_URL =
          if ollamaUrl == null
          then ""
          else ollamaUrl;
      };
    };
  };
}
