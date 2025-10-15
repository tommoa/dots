{ pkgs, ... }:

{
  home.packages = with pkgs; [
    google-cloud-sdk # This is required for using Vertex AI.
    ollama
    opencode
  ];
}
