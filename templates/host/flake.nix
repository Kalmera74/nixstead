{
  description = "NixOS host built with the Nixstead module API";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixstead = {
      url = "github:Kalmera74/nixstead";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixstead,
    ...
  }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixstead.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
