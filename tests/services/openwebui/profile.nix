{
  pkgs,
  lib,
  ...
}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./client.py;
    })
  ];
  sops.secrets = {
    "fixture/adminPassword" = {};
    "fixture/userPassword" = {};
    "fixture/otherPassword" = {};
  };
  nixstead.services.localai.openwebui = {
    enable = true;
    port = 28081;
  };
  services.open-webui.environment = {
    OFFLINE_MODE = "True";
    HF_HUB_OFFLINE = "1";
    TRANSFORMERS_OFFLINE = "1";
    ENABLE_OPENAI_API = "False";
    RAG_EMBEDDING_ENGINE = "ollama";
    RAG_EMBEDDING_MODEL = "fixture-stories:latest";
    RAG_EMBEDDING_MODEL_AUTO_UPDATE = "False";
    WHISPER_MODEL_AUTO_UPDATE = "False";
    AIOHTTP_CLIENT_TIMEOUT = "30";
  };
  environment.etc."openwebui-fixture.py".source = ./client.py;
  systemd.tmpfiles.rules = ["d /var/lib/openwebui-fixture-evidence 0700 root root -"];
  environment.systemPackages = [pkgs.python3];
  virtualisation.memorySize = lib.mkForce 3072;
}
