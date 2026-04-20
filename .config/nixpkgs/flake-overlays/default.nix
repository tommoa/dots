inputs: self: super: {
  opencode =
    inputs.opencode.packages.${super.stdenv.hostPlatform.system}.default.overrideAttrs
    (old: {
      preBuild =
        (old.preBuild or "")
        + ''
          substituteInPlace packages/opencode/src/cli/cmd/generate.ts \
            --replace-fail 'const prettier = await import("prettier")' 'const prettier: any = { format: async (s: string) => s }' \
            --replace-fail 'const babel = await import("prettier/plugins/babel")' 'const babel = {}' \
            --replace-fail 'const estree = await import("prettier/plugins/estree")' 'const estree = {}'
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
