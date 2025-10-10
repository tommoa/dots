{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bun
    nodejs
    typescript
    typescript-language-server
  ];
}
