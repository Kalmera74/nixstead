{
  config,
  host,
  ...
}: {
  networking.hostName = config.nixstead.host.hostName;

  networking.networkmanager.enable = true;

  services.openssh = {
    enable = true;
    ports = [config.nixstead.host.ports.ssh];
    settings = {
      PasswordAuthentication = config.nixstead.host.ssh.passwordAuthentication;
      KbdInteractiveAuthentication = config.nixstead.host.ssh.passwordAuthentication;
      PermitRootLogin = config.nixstead.host.ssh.rootLogin;
    };
  };

  networking.firewall.allowedTCPPorts = [
    config.nixstead.host.ports.ssh
  ];
}
