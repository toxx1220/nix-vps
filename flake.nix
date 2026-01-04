{
  description = "NixOS VPS with MicroVMs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
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
    # Add your service repos as inputs
    nannuo-bot = {
      url = "github:toxx1220/nannuo-bot";
    };
    bgs-backend = {
      url = "github:toxx1220/bgs_backend_V2";
    };
  };

  outputs = { self, nixpkgs, disko, microvm, sops-nix, nannuo-bot, bgs-backend, ... }@inputs: {
    nixosConfigurations.vps = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      # Pass inputs to all modules
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        ./disko.nix
        ./host.nix
        microvm.nixosModules.host
        sops-nix.nixosModules.sops
      ];
    };
  };
}
