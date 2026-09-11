{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    networkmanager
    croc
    nethogs
  ];
}
