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

  obsidian = super.obsidian.overrideAttrs (old:
    if super.stdenv.isDarwin
    then {
      sourceRoot = "Obsidian ${old.version}-universal/Obsidian.app";
    }
    else {}
  );
}
// (import ./w3m.nix self super)
// (import ./aerc.nix self super)
