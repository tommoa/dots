{
  description = "Tom's modular nix systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.11";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, nix-darwin, home-manager, ... }:
    let
      zen-browser-module = inputs.zen-browser.homeModules.twilight-official;

      # Overlay that provides access to nixpkgs-unstable packages
      unstablePackages = final: prev: {
        unstable = import inputs.nixpkgs-unstable { inherit (prev) system; };
      };

      # Helper function to create home-manager configurations
      mkHomeConfig = { username, homeDirectory, system, profiles ? [ "base" "development" ] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              unstablePackages
              (import ./overlays)
            ];
          };
          modules = [
            zen-browser-module
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
          modules = [
            hostConfig
            {
              nixpkgs.overlays = [
                unstablePackages
                (import ./overlays)
              ];
            }
            home-manager.darwinModules.home-manager {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${username} = { ... }: {
                imports = [
                  zen-browser-module
                ] ++ map (profile: ./modules/home-manager/profiles/${profile}.nix) homeProfiles;
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
          modules = [
            hostConfig
            {
              nixpkgs.overlays = [
                unstablePackages
                (import ./overlays)
              ];
            }
            home-manager.nixosModules.home-manager {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${username} = { ... }: {
                imports = [
                  zen-browser-module
                ] ++ map (profile: ./modules/home-manager/profiles/${profile}.nix) homeProfiles;
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
