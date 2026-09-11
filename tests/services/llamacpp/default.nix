{
  stateful = false;
  paths = ["modules/services/localai/llama-cpp.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Independent child selection; native model/context/threads and managed listeners, Ollama dependency/read-only model bind, proxy/card/firewall.";
    };
    runtime = {
      file = ./runtime.nix;
      systems = ["x86_64-linux"];
      covers = ["runtime"];
      detail = "Native llama.cpp starts with the small immutable GGUF fixture and reaches its configured loopback health endpoint.";
    };
  };
  limitations = ["The 19 MB TinyStories GGUF exists only so the native server can start. Inference semantics, model-loss behavior, restart/reboot, production quality, large-model capacity, GPU, ARM runtime and cross-version behavior remain unverified by this smoke. Read-only source bytes are configuration-owned; no unique model or retained-output backup is implied."];
}
