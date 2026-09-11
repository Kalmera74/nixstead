{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  configured =
    (mkSystem [
      {
        nixstead.services.localai.llamacpp = {
          enable = true;
          port = 28084;
          settings = {
            model = "/srv/models/test.gguf";
            "ctx-size" = 1024;
            threads = 2;
            host = "0.0.0.0";
            port = 1;
          };
        };
      }
    ]).config;
  backed =
    (mkSystem [
      {
        nixstead.services.localai = {
          ollama = {
            enable = true;
            paths.modelsDir = "/srv/ollama";
          };
          llamacpp = {
            enable = true;
            ollamaModel = "fixture:tiny";
            settings.model = "/unowned.gguf";
          };
        };
      }
    ]).config;
  missing =
    (mkSystem [
      {
        nixstead.services.localai.llamacpp = {
          enable = true;
          ollamaModel = "fixture:tiny";
        };
      }
    ]).config;
in
  (serviceContract {
    id = "llamacpp";
    group = "localai";
    port = 28084;
    nativeEnabled = c: c.services.llama-cpp.enable;
  })
  // {
    nativeModelAndResources = configured.services.llama-cpp.settings.model == "/srv/models/test.gguf" && configured.services.llama-cpp.settings."ctx-size" == 1024 && configured.services.llama-cpp.settings.threads == 2;
    managedListenerWins = configured.services.llama-cpp.settings.host == "127.0.0.1" && configured.services.llama-cpp.settings.port == 28084;
    ollamaRequiresEnabledDependency = lib.any (a: !a.assertion && lib.hasInfix "requires the local Ollama" a.message) missing.assertions;
    ollamaReadOnlyModelMount = lib.elem "/srv/ollama:/run/llama-cpp/ollama-models" backed.systemd.services.llama-cpp.serviceConfig.BindReadOnlyPaths;
    ollamaDependency = lib.elem "ollama.service" backed.systemd.services.llama-cpp.requires && !(backed.services.llama-cpp.settings ? model);
    noInferenceStateBackup = configured.nixstead.serviceRegistry.llamacpp.backup == null;
  }
