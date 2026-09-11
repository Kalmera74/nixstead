{pkgs, ...}: let
  model = import ../../fixtures/tiny-story-model.nix {inherit pkgs;};
in {
  nixstead.services.localai.llamacpp = {
    enable = true;
    port = 28084;
    settings = {
      model = "/srv/llama-fixture/model.gguf";
      alias = "fixture-stories";
      "ctx-size" = 128;
      threads = 1;
      "threads-batch" = 1;
      parallel = 1;
      "n-gpu-layers" = 0;
    };
  };
  system.activationScripts.llama-fixture-model.text = ''
    install -d -m 0755 /srv/llama-fixture
    if [ ! -e /srv/llama-fixture/model.gguf ]; then
      install -m 0444 ${model} /srv/llama-fixture/model.gguf
    fi
  '';
  virtualisation.memorySize = 768;
  virtualisation.diskSize = 4096;
}
