{...}: {
  imports = [
    ./ai-tools/ai-proxy.nix
    ./ai-tools/codex.nix
    ./ai-tools/opencode.nix
    ./ai-tools/pi.nix
    ./ai-tools/skills.nix
    ./ai-tools/t3code.nix
  ];

  config = {
    programs.mcp.enable = true;
  };
}
