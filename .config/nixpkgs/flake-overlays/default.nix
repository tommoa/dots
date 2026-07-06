inputs: self: super: let
  unstable = import inputs.nixpkgs-unstable {
    system = super.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };

  neovim-unwrapped-wasm = unstable.neovim-unwrapped.override {
    wasmSupport = true;
  };
in {
  neovim-unwrapped = neovim-unwrapped-wasm;
  neovim = unstable.wrapNeovim neovim-unwrapped-wasm {};

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
