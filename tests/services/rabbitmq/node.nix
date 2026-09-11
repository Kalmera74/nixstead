{
  config,
  pkgs,
  ...
}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  networking.hostName = "broker-fixture";
  nixstead.services.dev.rabbitmq = {
    enable = true;
    port = 25673;
  };
  services.rabbitmq.dataDir = "/srv/rabbitmq";
  environment.systemPackages = [config.services.rabbitmq.package];
  virtualisation.memorySize = 1536;
}
