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

  chatgpt-desktop = inputs.codex-desktop-linux.packages.${super.stdenv.hostPlatform.system}.default;
  codex = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.codex;
  opencode = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.opencode;
  pi-coding-agent = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.pi;
}
