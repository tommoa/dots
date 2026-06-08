inputs: self: super: let
  patchOpencodeSource = old: {
    preBuild =
      (old.preBuild or "")
      + ''
        substituteInPlace package.json \
          --replace-fail '"packageManager": "bun@1.3.14"' '"packageManager": "bun@1.3.13"'
      '';
  };
in {
  opencode = inputs.opencode.packages.${super.stdenv.hostPlatform.system}.default.overrideAttrs (
    old:
      (patchOpencodeSource old)
      // {
        preBuild =
          (old.preBuild or "")
          + ''
            substituteInPlace package.json \
              --replace-fail '"packageManager": "bun@1.3.14"' '"packageManager": "bun@1.3.13"'

            substituteInPlace packages/opencode/src/cli/cmd/generate.ts \
              --replace-fail 'const prettier = await import("prettier")' 'const prettier: any = { format: async (s: string) => s }' \
              --replace-fail 'const babel = await import("prettier/plugins/babel")' 'const babel = {}' \
              --replace-fail 'const estree = await import("prettier/plugins/estree")' 'const estree = {}'
          '';
      }
  );

  opencode-desktop =
    inputs.opencode.packages.${super.stdenv.hostPlatform.system}.opencode-desktop.overrideAttrs
    patchOpencodeSource;

  hunk = inputs.hunk.packages.${super.stdenv.hostPlatform.system}.default;
}
