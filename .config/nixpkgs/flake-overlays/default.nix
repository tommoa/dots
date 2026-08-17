inputs: self: super: let
  unstable = import inputs.nixpkgs-unstable {
    system = super.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };

  neovim-unwrapped-wasm = unstable.neovim-unwrapped.override {
    wasmSupport = true;
  };
in {
  # Zen Browser currently requires ffmpeg_9, while the 26.05 release
  # nixpkgs followed by this flake still exposes ffmpeg_7. Reuse the
  # already-pinned unstable package so Zen's package and wrapper can resolve
  # the dependency without moving the whole system to unstable.
  ffmpeg_9 = unstable.ffmpeg_9;

  neovim-unwrapped = neovim-unwrapped-wasm;
  neovim = unstable.wrapNeovim neovim-unwrapped-wasm {};

  chatgpt-desktop = inputs.codex-desktop-linux.packages.${super.stdenv.hostPlatform.system}.default;
  codex = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.codex;
  opencode = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.opencode;
  pi-coding-agent = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.pi;
}
