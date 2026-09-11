{...}: {
  imports = [
    ./external.nix
    ./container-image-overrides.nix
    ./arr/arr.nix
    ./cifs/cifs.nix
    ./media/media.nix
    ./nas/nas.nix
    ./productivity/productivity.nix
    ./dev/dev.nix
    ./localai/localai.nix
    ./vaultwarden.nix
    ./homeassistant.nix
    ./authentik.nix
    ./syncthing.nix
    ./scrutiny.nix
    ./tailscale.nix
    ./wireguard.nix
    ./nginx/nginx.nix
    ./homepage/homepage.nix
    ./registry-integrations.nix
    ./presets.nix
  ];
}
