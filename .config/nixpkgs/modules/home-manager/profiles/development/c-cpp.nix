{ pkgs, ... }:

{
  home.packages = with pkgs; [
    clang
    clang-tools
    gdb
  ];
}
