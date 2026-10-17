{
  description = "Amchelle's NixOS flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix }: 
    let
      shellsFor = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in pkgs.mkShell {
          sopsPGPKeyDirs = [
            "${toString ./.}/keys/hosts"
            "${toString ./.}/keys/users"
          ];
          nativeBuildInputs = [
            (pkgs.callPackage sops-nix {}).sops-import-keys-hook
          ];
        };
      system = "x86_64-linux";
      user = "amchelle";
      lib = nixpkgs.lib;
    in
    {
      devShells.x86_64-linux.default = shellsFor "x86_64-linux";
      devShells.aarch64-darwin.default = shellsFor "aarch64-darwin";

      nixosConfigurations = {
        elaine = lib.nixosSystem {
          inherit system;
          modules = [ 
            ./configuration.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${user} = {
                imports = [ ./home.nix ];
              };
            }             
          ];
        };
      };
    };
}
