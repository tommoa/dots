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

  hunk = super.callPackage ../packages/hunk {};
}
// (import ./yabai.nix self super)
// (import ./w3m.nix self super)
// (import ./aerc.nix self super)
