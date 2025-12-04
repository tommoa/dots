{ pkgs, ... }:

{
  # AI tool packages
  # Secrets are defined in secrets/ai.nix or secrets/ai-vertex.nix
  home.packages = with pkgs; [
    google-cloud-sdk # This is required for using Vertex AI.
    opencode
    # ollama is broken on darwin with 25.11
    # https://github.com/NixOS/nixpkgs/issues/463131
  ] ++ (if pkgs.stdenv.isLinux then [ollama] else []);
}
