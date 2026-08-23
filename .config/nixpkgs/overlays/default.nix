self: super:
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
