{
  stateful = null;
  paths = ["modules/services/localai/stable-diffusion-cpp.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent child selection; split models and mount conditions, native command/resource overrides, missing/duplicate/reserved model rejection, proxy/card/firewall.";
  };
  limitations = [
    "Healthy native startup is unverified: sd-server loads a complete compatible model before listening, and the fast suite has no small compatible checkpoint fixture."
    "Image generation, retained output/asset recovery and GPU profiles remain unverified."
  ];
}
