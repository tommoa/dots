{
  description = "Tom's modular nix systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.11";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

    opencode = {
      url = "github:sst/opencode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
      inputs.home-manager.follows = "home-manager";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.darwin.follows = "nix-darwin";
    };
  };

  outputs = inputs @ {
    nixpkgs,
    nix-darwin,
    home-manager,
    ...
  }: let
    zen-browser-module = inputs.zen-browser.homeModules.twilight-official;

    # Path to agenix secrets (relative to flake)
    secretsPath = ./secrets;

    # Agenix home-manager module that also adds the CLI and defines secretsPath option
    agenix-module = {
      pkgs,
      lib,
      ...
    }: {
      imports = [inputs.agenix.homeManagerModules.default];

      options.my.secretsPath = lib.mkOption {
        type = lib.types.path;
        default = secretsPath;
        readOnly = true;
        description = "Path to agenix secrets directory";
      };

      config = {
        home.packages = [inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default];
      };
    };

    # Helper function to create home-manager configurations
    mkHomeConfig = {
      username,
      homeDirectory,
      system,
      profiles ? [
        "base"
        "development"
      ],
      extraModules ? [],
    }:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            (import ./overlays inputs)
          ];
        };
        modules =
          [
            agenix-module
            zen-browser-module
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
              nixpkgs.config.allowUnfree = true;
            }
          ]
          ++ map (profile: ./modules/home-manager/profiles/${profile}.nix) profiles
          ++ extraModules;
      };

    # Helper function to create darwin configurations
    mkDarwinConfig = {
      hostConfig,
      username,
      homeDirectory,
      homeProfiles ? [
        "base"
        "development"
        "desktop"
      ],
    }:
      nix-darwin.lib.darwinSystem {
        modules = [
          hostConfig
          inputs.agenix.darwinModules.default
          {
            nixpkgs.overlays = [
              (import ./overlays inputs)
            ];
          }
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [
              agenix-module
            ];
            home-manager.users.${username} = {...}: {
              imports =
                [
                  zen-browser-module
                ]
                ++ map (profile: ./modules/home-manager/profiles/${profile}.nix) homeProfiles;
              home.username = username;
              home.homeDirectory = homeDirectory;
            };
          }
        ];
        specialArgs = {inherit inputs;};
      };

    # Helper function to create nixos configurations
    mkNixosConfig = {
      hostConfig,
      username,
      homeDirectory,
      homeProfiles ? [
        "base"
        "development"
        "desktop"
      ],
    }:
      nixpkgs.lib.nixosSystem {
        modules = [
          hostConfig
          inputs.agenix.nixosModules.default
          {
            nixpkgs.overlays = [
              (import ./overlays inputs)
            ];
          }
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [
              agenix-module
            ];
            home-manager.users.${username} = {...}: {
              imports =
                [
                  zen-browser-module
                ]
                ++ map (profile: ./modules/home-manager/profiles/${profile}.nix) homeProfiles;
              home.username = username;
              home.homeDirectory = homeDirectory;
            };
          }
        ];
        specialArgs = {inherit inputs;};
      };
  in {
    # Standalone home-manager configurations
    homeConfigurations = {
      # Work desktop (macOS)
      "toma@work" = mkHomeConfig {
        username = "toma";
        homeDirectory = "/Users/toma";
        system = "aarch64-darwin";
        profiles = [
          "base"
          "desktop"
          "development"
          "secrets/ai"
          "secrets/deploy-keys"
          "ssh"
          "ssh/work"
        ];
      };

      # Personal desktop (Linux)
      "tommoa@personal" = mkHomeConfig {
        username = "tommoa";
        homeDirectory = "/home/tommoa";
        system = "x86_64-linux";
        profiles = [
          "base"
          "desktop"
          "development"
          "secrets/ai"
          "secrets/deploy-keys"
          "ssh"
          "ssh/personal"
        ];
      };

      # Server deployments (headless)
      "toma@server" = mkHomeConfig {
        username = "toma";
        homeDirectory = "/home/toma";
        system = "x86_64-linux";
        # c/cpp not allowed as they would shadow the work tools.
        # Server only gets Vertex AI keys, no deploy keys.
        profiles = [
          "base"
          "development/ai-tools"
          "development/javascript"
          "development/lua"
          "development/nix"
          "development/python"
          "secrets/ai-vertex"
          "ssh"
        ];
        extraModules = [
          {my.opencode.disablePythonFormatters = true;}
        ];
      };

      "tommoa@server" = mkHomeConfig {
        username = "tommoa";
        homeDirectory = "/home/tommoa";
        system = "x86_64-linux";
        profiles = [
          "base"
          "development"
          "secrets/ai-vertex"
          "server"
          "ssh"
        ];
      };
    };

    # System configurations
    darwinConfigurations."apollo" = mkDarwinConfig {
      hostConfig = ./hosts/apollo.nix;
      username = "toma";
      homeDirectory = "/Users/toma";
      homeProfiles = [
        "base"
        "desktop"
        "development"
        "mail"
        "secrets/ai"
        "secrets/deploy-keys"
        "ssh"
        "ssh/work"
      ];
    };

    nixosConfigurations."james" = mkNixosConfig {
      hostConfig = ./hosts/james.nix;
      username = "tommoa";
      homeDirectory = "/home/tommoa";
      homeProfiles = [
        "base"
        "desktop"
        "development"
        "mail"
        "secrets/ai"
        "secrets/deploy-keys"
        "ssh"
        "ssh/personal"
      ];
    };

    # Formatter for `nix fmt`
    formatter = {
      x86_64-linux = (import nixpkgs {system = "x86_64-linux";}).alejandra;
      aarch64-darwin = (import nixpkgs {system = "aarch64-darwin";}).alejandra;
      aarch64-linux = (import nixpkgs {system = "aarch64-linux";}).alejandra;
    };
  };
}
