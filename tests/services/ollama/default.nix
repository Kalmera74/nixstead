{
  stateful = true;
  paths = ["modules/services/localai/ollama.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent child selection; native loopback/model mount/media access, CPU package default, custom port/proxy/card/firewall and invalid model path.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Native Ollama starts with the configured custom model directory and reaches its loopback version endpoint.";
  };
  limitations = ["Model import/inference, model persistence or backup, restart/reboot, malformed requests, remote registries, GPU, ARM runtime, large models and cross-version execution are unverified by this startup smoke. Unique imported weights and definitions remain user-owned durable state without a passing archive recovery fixture."];
}
