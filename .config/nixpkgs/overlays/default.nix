self: super:
{
  arista-browser-extension = import ../packages/arista-browser-extension {
    inherit (super)
      buildNpmPackage
      fetchFromGitiles
      jq
      lib
      nodejs_22
      runCommand
      zip
      ;
  };

  arista-browser-extension-signed = import ../packages/arista-browser-extension/signed.nix {
    inherit (super) requireFile;
  };

  update-arista-browser-extension = super.writeShellApplication {
    name = "update-arista-browser-extension";
    runtimeInputs = with super; [
      coreutils
      diffutils
      git
      gnused
      jq
      nix
      nodejs_22
      openssh
      prefetch-npm-deps
      unzip
      web-ext
    ];
    text = builtins.readFile ../packages/arista-browser-extension/update.sh;
    meta.mainProgram = "update-arista-browser-extension";
  };

  # Claude Code to OpenCode plugin transformer
  claude-to-opencode = import ../packages/claude-to-opencode {
    inherit
      (super)
      lib
      python3
      runCommand
      writeShellScriptBin
      symlinkJoin
      buildNpmPackage
      nodejs
      ;
  };

  obsidian-headless = import ../packages/obsidian-headless {
    inherit
      (super)
      buildNpmPackage
      lib
      makeWrapper
      nodejs_24
      python3
      stdenv
      ;
  };
}
// (import ./w3m.nix self super)
// (import ./aerc.nix self super)
