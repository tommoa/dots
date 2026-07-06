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
          grep -Eq '"packageManager"[[:space:]]*:[[:space:]]*"bun@[^"]+"' package.json
          sed -i -E 's/"packageManager"[[:space:]]*:[[:space:]]*"bun@[^"]+"/"packageManager": "bun@${unstable.bun.version}"/' package.json
        '';
    });

  pi-coding-agent = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.pi;
}
