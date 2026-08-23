{
  description = "NixOS VPS with Native Containers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    comin = {
      url = "github:nlewo/comin";
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
    bgs-backend = {
      url = "github:toxx1220/bgs_backend_V2";
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
              pkgs.nil
              pkgs.rustc
              pkgs.rustfmt
              pkgs.rust-analyzer
            ];
            # Set RUST_SRC_PATH for rust-analyzer
            env.RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
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
            inputs.comin.nixosModules.comin
          ];
        };
      };
    };
}
