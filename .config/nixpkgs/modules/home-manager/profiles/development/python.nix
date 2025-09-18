{ pkgs, ... }:

{
  home.packages = with pkgs; [
    uv
    pyright
    python3Packages.debugpy
  ];
}
