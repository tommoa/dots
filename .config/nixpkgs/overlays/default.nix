inputs: self: super:
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
      ;
  };

  opencode = inputs.opencode.packages.${super.stdenv.hostPlatform.system}.default;
}
// (import ./yabai.nix self super)
// (import ./whatsapp.nix self super)
