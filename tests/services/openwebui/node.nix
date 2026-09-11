{lib, ...}: {
  nixstead.services.localai.openwebui = {
    enable = true;
    port = 28081;
    ollamaUrl = "http://127.0.0.1:21434";
  };
  services.open-webui.environment = {
    OFFLINE_MODE = "True";
    HF_HUB_OFFLINE = "1";
    TRANSFORMERS_OFFLINE = "1";
    ENABLE_OPENAI_API = "False";
    RAG_EMBEDDING_ENGINE = "ollama";
    RAG_EMBEDDING_MODEL_AUTO_UPDATE = "False";
    WHISPER_MODEL_AUTO_UPDATE = "False";
  };
  virtualisation.memorySize = lib.mkForce 3072;
}
