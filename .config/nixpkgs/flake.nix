{
  description = "Tom's modular nix systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
  };

  outputs = inputs@{ nixpkgs, nix-darwin, home-manager, ... }:
    let
      # Helper function to create home-manager configurations
      mkHomeConfig = { username, homeDirectory, system, profiles ? [ "base" "development" ] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ (import ./overlays) ];
          };
          modules = [
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
              nixpkgs.config.allowUnfree = true;
            }
          ] ++ map (profile: ./modules/home-manager/profiles/${profile}.nix) profiles;
        };

      # Helper function to create darwin configurations
      mkDarwinConfig = { hostConfig, username, homeDirectory, homeProfiles ? [ "base" "development" "desktop" ] }:
        nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            hostConfig
            home-manager.darwinModules.home-manager {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${username} = { ... }: {
                imports = map (profile: ./modules/home-manager/profiles/${profile}.nix) homeProfiles;
                home.username = username;
                home.homeDirectory = homeDirectory;
              };
            }
          ];
          specialArgs = { inherit inputs; };
        };

      # Helper function to create nixos configurations  
      mkNixosConfig = { hostConfig, username, homeDirectory, homeProfiles ? [ "base" "development" "desktop" ] }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            hostConfig
            home-manager.nixosModules.home-manager {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${username} = { ... }: {
                imports = map (profile: ./modules/home-manager/profiles/${profile}.nix) homeProfiles;
                home.username = username;
                home.homeDirectory = homeDirectory;
              };
            }
          ];
          specialArgs = { inherit inputs; };
        };
    in
    {
      # Standalone home-manager configurations
      homeConfigurations = {
        # Work desktop (macOS)
        "toma@work" = mkHomeConfig {
          username = "toma";
          homeDirectory = "/Users/toma";
          system = "aarch64-darwin";
          profiles = [ "base" "development" "desktop" ];
        };

        # Personal desktop (Linux)
        "tommoa@personal" = mkHomeConfig {
          username = "tommoa";
          homeDirectory = "/home/tommoa";
          system = "x86_64-linux";
          profiles = [ "base" "development" "desktop" ];
        };

        # Server deployments (headless)
        "toma@server" = mkHomeConfig {
          username = "toma";
          homeDirectory = "/home/toma";
          system = "x86_64-linux";
          # c/cpp not allowed as they would shadow the work tools.
          profiles = [
            "base"
            "development/ai-tools"
            "development/javascript"
            "development/lua"
            "development/nix"
            "development/python"
          ];
        };

        "tommoa@server" = mkHomeConfig {
          username = "tommoa";
          homeDirectory = "/home/tommoa";
          system = "x86_64-linux";
          profiles = [ "base" "development" "server" ];
        };
      };

      # System configurations
      darwinConfigurations."apollo" = mkDarwinConfig {
        hostConfig = ./hosts/apollo.nix;
        username = "toma";
        homeDirectory = "/Users/toma";
      };

      nixosConfigurations."james" = mkNixosConfig {
        hostConfig = ./hosts/james.nix;
        username = "tommoa";
        homeDirectory = "/home/tommoa";
      };
    };
}
