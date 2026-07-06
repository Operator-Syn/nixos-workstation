{
  description = "A Modular NixOS Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    nur.url = "github:nix-community/NUR";

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    username = "yashindo";

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    pkgsUnstable = import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit inputs pkgsUnstable;
      };

      modules = [
        ./hosts/hiraeth

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {
            inherit inputs pkgsUnstable;
          };
          # Avoid collisions with old application-managed *.backup files
          # when Home Manager needs to migrate paths into managed symlinks.
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.${username} = import ./home/yashindo;
        }
      ];
    };

    devShells.${system} = import ./devshells {
      inherit pkgs;
    };

    formatter.${system} = pkgs.alejandra;
  };
}
