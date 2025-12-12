{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Runtimes (use `bun --inspect` + debug.bun.sh for debugging)
    bun
    nodejs

    # Language tooling
    typescript
    typescript-language-server
  ];
}
