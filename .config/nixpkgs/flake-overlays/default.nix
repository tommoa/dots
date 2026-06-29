inputs: self: super: {
  codex = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.codex;

  opencode = inputs.opencode.packages.${super.stdenv.hostPlatform.system}.default;

  opencode-desktop =
    inputs.opencode.packages.${super.stdenv.hostPlatform.system}.opencode-desktop.overrideAttrs
    (old: {
      preBuild =
        (old.preBuild or "")
        + ''
          substituteInPlace package.json \
            --replace-fail '"packageManager": "bun@1.3.14"' '"packageManager": "bun@1.3.13"'
        '';
    });

  pi-coding-agent = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.pi;
}
