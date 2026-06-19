{
  description = "Tom's modular nix systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-26.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    opencode = {
      url = "github:anomalyco/opencode";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    hunk = {
      url = "github:modem-dev/hunk";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
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
    zen-browser-module = inputs.zen-browser.homeModules.beta;

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
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [
              # bitwarden-desktop still depends on electron_39 in nixpkgs 26.05.
              "electron-39.8.10"
            ];
          };
          overlays = [
            (import ./overlays)
            (import ./flake-overlays inputs)
          ];
        };
        modules =
          [
            agenix-module
            zen-browser-module
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
              nixpkgs.config = {
                allowUnfree = true;
                permittedInsecurePackages = [
                  # bitwarden-desktop still depends on electron_39 in nixpkgs 26.05.
                  "electron-39.8.10"
                ];
              };
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
              (import ./overlays)
              (import ./flake-overlays inputs)
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
              targets.darwin.copyApps.enable = false;
              targets.darwin.linkApps.enable = true;
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
              (import ./overlays)
              (import ./flake-overlays inputs)
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
          "secrets/ai-work"
          "secrets/arista-report"
          "secrets/deploy-keys"
          "ssh"
          "ssh/work"
        ];
        extraModules = [
          {
            my.pi.enable = true;
            my.pi.package = inputs.llm-agents.packages.x86_64-linux.pi;
          }
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
        # Server only gets work AI keys, no deploy keys.
        profiles = [
          "base"
          "development/ai-tools"
          "development/javascript"
          "development/lua"
          "development/nix"
          "development/python"
          "secrets/ai-work"
          "ssh"
        ];
        extraModules = [
          {
            my.opencode.enable = true;
            my.opencode.disablePythonFormatters = true;
            my.pi.enable = true;
            my.pi.package = inputs.llm-agents.packages.x86_64-linux.pi;
          }
        ];
      };

      "tommoa@server" = mkHomeConfig {
        username = "tommoa";
        homeDirectory = "/home/tommoa";
        system = "x86_64-linux";
        profiles = [
          "base"
          "development"
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
        "secrets/ai-work"
        "secrets/arista-report"
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
        "secrets/keyring-unlock"
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

    # Packages
    packages = let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
      forAllSystems (
        system: let
          pkgs = import nixpkgs {inherit system;};
        in {
          claude-to-opencode =
            (import ./packages/claude-to-opencode {
              inherit
                (pkgs)
                lib
                python3
                runCommand
                writeShellScriptBin
                symlinkJoin
                buildNpmPackage
                nodejs
                ;
            }).package;
          hunk = inputs.hunk.packages.${system}.default;
        }
      );
  };
}
