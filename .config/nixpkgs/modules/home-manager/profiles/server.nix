{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Server-specific tools
    htop
    curl
    wget
    rsync
  ];
}
