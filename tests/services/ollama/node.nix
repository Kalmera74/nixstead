{...}: {
  nixstead.services.localai.ollama = {
    enable = true;
    port = 21434;
    paths.modelsDir = "/srv/ollama-models";
  };
  services.ollama.environmentVariables = {
    OLLAMA_NUM_PARALLEL = "1";
    OLLAMA_MAX_LOADED_MODELS = "1";
    OLLAMA_CONTEXT_LENGTH = "128";
    OLLAMA_NO_CLOUD = "1";
  };
  systemd.tmpfiles.rules = ["d /srv/ollama-models 0700 ollama ollama -"];
  virtualisation.memorySize = 768;
  virtualisation.diskSize = 4096;
}
