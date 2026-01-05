{
  description = "NixOS VPS with MicroVMs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nannuo-bot = { url = "github:toxx1220/nannuo-bot"; };
    bgs-backend = { url = "github:toxx1220/bgs_backend_V2?dir=deployment"; };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems =
        [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        devShells.default =
          pkgs.mkShell { packages = [ pkgs.nixpkgs-fmt pkgs.sops ]; };
      };
      flake = {
        nixosConfigurations.vps-arm = inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            inherit inputs;
            device = "/dev/sda"; # TODO: run lsblk before deployment to check if this is correct
          };
          modules = [
            inputs.disko.nixosModules.disko
            inputs.impermanence.nixosModules.impermanence
            ./disko.nix
            ./host.nix
            inputs.microvm.nixosModules.host
            inputs.sops-nix.nixosModules.sops
          ];
        };
      };
    };
}
