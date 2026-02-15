{
  description = "NixOS VPS with Native Containers";

  nixConfig = {
    extra-substituters = [
      "https://cache.garnix.io"
    ];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    garnix-lib = {
      url = "github:garnix-io/garnix-lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    nannuo-bot = {
      url = "github:toxx1220/nannuo-bot";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      flakeName = "vps-arm";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      perSystem =
        {
          config,
          pkgs,
          ...
        }:
        {
          treefmt.config = import ./treefmt.nix;

          devShells.default = pkgs.mkShell {
            packages = [
              config.treefmt.build.wrapper
              pkgs.sops
            ];
          };
        };
      flake = {
        nixosConfigurations.${flakeName} = inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            inherit inputs;
            device = "/dev/sda";
            inherit flakeName;
          };
          modules = [
            inputs.disko.nixosModules.disko
            inputs.impermanence.nixosModules.impermanence
            ./disko.nix
            ./host.nix
            inputs.sops-nix.nixosModules.sops
            inputs.garnix-lib.nixosModules.garnix
          ];
        };
      };
    };
}
