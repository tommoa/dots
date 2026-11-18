inputs: self: super: let
  unstable = import inputs.nixpkgs-unstable {
    system = super.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };

  t3codePackages = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system};
  t3codeUnwrapped = t3codePackages.t3code.unwrapped.overrideAttrs (old: {
    # The frontend hides T3 Connect unless its build includes the JWT template.
    # Upstream fix: https://github.com/numtide/llm-agents.nix/pull/11699
    env = old.env // {T3CODE_CLERK_JWT_TEMPLATE = "t3-relay";};
  });

  neovim-unwrapped-wasm =
    (unstable.neovim-unwrapped.override {
      wasmSupport = true;
    }).overrideAttrs (old: {
      postPatch =
        builtins.replaceStrings
        ["find_package(Wasmtime 36.0.6 EXACT REQUIRED)"]
        ["find_package(Wasmtime 36.0 EXACT REQUIRED)"]
        old.postPatch;
    });
in {
  # Zen Browser currently requires ffmpeg_9, while the 26.05 release
  # nixpkgs followed by this flake still exposes ffmpeg_7. Reuse the
  # already-pinned unstable package so Zen's package and wrapper can resolve
  # the dependency without moving the whole system to unstable.
  ffmpeg_9 = unstable.ffmpeg_9;

  neovim-unwrapped = neovim-unwrapped-wasm;
  neovim = unstable.wrapNeovim neovim-unwrapped-wasm {};

  chatgpt-desktop = inputs.codex-desktop-linux.packages.${super.stdenv.hostPlatform.system}.default;
  codex = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.codex.overrideAttrs (old: {
    # AWS-LC 5 uses prefixed symbols and no longer provides openssl.pc by
    # default. Supply OpenSSL separately for Codex's native-tls dependency.
    buildInputs = old.buildInputs ++ [unstable.openssl];
  });
  opencode = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.opencode;
  opencode2 = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.opencode2;
  pi-coding-agent = inputs.llm-agents.packages.${super.stdenv.hostPlatform.system}.pi;
  t3code = t3codePackages.t3code.override {
    codex = self.codex;
    t3code-unwrapped = t3codeUnwrapped;
  };
  t3code-desktop = t3codePackages.t3code-desktop.override {t3code = self.t3code;};
}
