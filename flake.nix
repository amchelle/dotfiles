{
  description = "Amchelle's macOS host and explicit Underclass clients";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Recent unstable with a cached Apple Silicon Atuin; avoid a local Rust build.
    atuin-nixpkgs.url = "github:NixOS/nixpkgs/8aa2baf1af6ca99131c979cbdadad7a08e2ca69a";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    underclass.url = "github:ghuntley/underclass/469aff4c797e14052285d64d9acfa4b2fc0c73a3";
  };

  outputs = inputs@{ nixpkgs, nix-darwin, home-manager, underclass, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
    in {
      darwinConfigurations."Amchelles-iMac" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.backupFileExtension = "pre-phoenix-20261017T131111Z";
            home-manager.users.amchellecrosson = import ./home.nix;
          }
        ];
      };
      packages.${system} = {
        underclass = underclass.packages.${system}.underclass;
        darwin-rebuild = nix-darwin.packages.${system}.darwin-rebuild;
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.git pkgs.curl pkgs.jq pkgs.sqlite pkgs.python3 ];
      };
    };
}
