{ pkgs, ... }:

{
  home.packages = with pkgs; [
    luajit
    lua-language-server # Includes built-in formatter (EmmyLuaCodeStyle)
  ];
}
