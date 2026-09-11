{
  mkService,
  localProxy,
  card,
  health,
  setup,
  credential,
  backup,
  ...
}: {
  ollama = mkService {
    name = "Ollama";
    optionPath = ["localai" "ollama"];
    defaults = {
      subdomain = "ollama";
      port = 11434;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "Local AI" 10 "Ollama" "ollama" "Local LLM";
    health = health "ollama.service";
    setup = setup "localai" 410 ["full"];
  };

  llamacpp = mkService {
    name = "llama.cpp";
    optionPath = ["localai" "llamacpp"];
    defaults = {
      subdomain = "llama";
      port = 8084;
    };
    firewall = true;
    proxy =
      localProxy
      // {
        extraLocationConfig = ''
          proxy_buffering off;
        '';
      };
    homepage = card "Local AI" 20 "llama.cpp" "llama-cpp" "GGUF Model Server";
    health = health "llama-cpp.service";
    setup = setup "localai" 420 ["full"];
  };

  stablediffusioncpp = mkService {
    name = "stable-diffusion.cpp";
    optionPath = ["localai" "stablediffusioncpp"];
    defaults = {
      subdomain = "stable";
      port = 1234;
    };
    firewall = true;
    proxy =
      localProxy
      // {
        extraLocationConfig = ''
          proxy_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          client_max_body_size 100m;
        '';
      };
    homepage = card "Local AI" 30 "stable-diffusion.cpp" "mdi-image-multiple" "Image and Video Generation";
    health = health "stable-diffusion-cpp.service";
    setup = setup "localai" 430 ["full"];
  };

  openwebui = mkService {
    name = "Open WebUI";
    optionPath = ["localai" "openwebui"];
    defaults = {
      subdomain = "ai";
      port = 8081;
    };
    firewall = true;
    proxy = localProxy // {websockets = true;};
    homepage = card "Local AI" 40 "Open WebUI" "open-webui" "AI UI";
    health = health "open-webui.service";
    credentials = [
      (credential.file {
        label = "email";
        pathOption = ["environmentFile"];
        envKey = "WEBUI_ADMIN_EMAIL";
        optional = true;
      })
      (credential.file {
        label = "password";
        pathOption = ["environmentFile"];
        envKey = "WEBUI_ADMIN_PASSWORD";
        optional = true;
      })
      (credential.manual "Create the first Open WebUI account through onboarding; it becomes the administrator.")
    ];
    backup =
      (backup "open-webui" "open-webui.service" "root" "root")
      // {
        # The CLI key lives beside data/, in its working directory. Stopping
        # the sole writer before staging keeps SQLite and uploads consistent.
        nativePathOption = ["services" "open-webui" "stateDir"];
        defaultPath = "/var/lib/open-webui";
        dynamicUser = true;
        requiredFilesWhenNativeEquals = [
          {
            option = ["services" "open-webui" "environment" "DATABASE_URL"];
            value = null;
            extraMatches = [
              {
                option = ["services" "open-webui" "environment" "DATA_DIR"];
                value = null;
              }
              {
                option = ["services" "open-webui" "environmentFile"];
                value = null;
              }
            ];
            files = ["data/webui.db"];
          }
          {
            option = ["services" "open-webui" "environment" "WEBUI_SECRET_KEY"];
            value = null;
            extraMatches = [
              {
                option = ["services" "open-webui" "environmentFile"];
                value = null;
              }
            ];
            files = [".webui_secret_key"];
          }
        ];
      };
    setup = setup "localai" 440 ["full"];
  };
}
