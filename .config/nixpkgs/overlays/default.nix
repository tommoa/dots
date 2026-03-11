inputs: self: super:
{
  # Claude Code to OpenCode plugin transformer
  claude-to-opencode = import ../packages/claude-to-opencode {
    inherit
      (super)
      lib
      python3
      runCommand
      writeShellScriptBin
      symlinkJoin
      ;
  };

  mdiff = super.callPackage ../packages/mdiff {};

  opencode =
    inputs.opencode.packages.${super.stdenv.hostPlatform.system}.default.overrideAttrs
    (old: {
      preBuild =
        (old.preBuild or "")
        + ''
          mkdir -p .github
          cp ${inputs.opencode}/.github/TEAM_MEMBERS .github/TEAM_MEMBERS
        '';
    });

  opencode-desktop = super.callPackage "${inputs.opencode}/nix/desktop.nix" {
    opencode = self.opencode;
    rustPlatform =
      super.rustPlatform
      // {
        buildRustPackage = f:
          super.rustPlatform.buildRustPackage (
            finalAttrs: let
              drv = f finalAttrs;
            in
              drv
              // {
                cargoLock =
                  (drv.cargoLock or {})
                  // {
                    outputHashes =
                      (drv.cargoLock.outputHashes or {})
                      // {
                        "specta-2.0.0-rc.22" = "sha256-YsyOAnXELLKzhNlJ35dHA6KGbs0wTAX/nlQoW8wWyJQ=";
                        "tauri-2.9.5" = "sha256-dv5E/+A49ZBvnUQUkCGGJ21iHrVvrhHKNcpUctivJ8M=";
                        "tauri-specta-2.0.0-rc.21" = "sha256-n2VJ+B1nVrh6zQoZyfMoctqP+Csh7eVHRXwUQuiQjaQ=";
                      };
                  };
              }
          );
      };
  };
}
// (import ./yabai.nix self super)
// (import ./whatsapp.nix self super)
// (import ./w3m.nix self super)
// (import ./aerc.nix self super)
