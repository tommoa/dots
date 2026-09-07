{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./ai-tools/ai-proxy.nix
    ./ai-tools/codex.nix
    ./ai-tools/opencode.nix
    ./ai-tools/pi.nix
    ./ai-tools/skills.nix
  ];

  config = {
    programs.mcp.enable = true;

    # AI tool packages
    # Secrets are defined in secrets/ai.nix.
    home.packages = lib.optionals pkgs.stdenv.isLinux [pkgs.ollama];
  };
}
