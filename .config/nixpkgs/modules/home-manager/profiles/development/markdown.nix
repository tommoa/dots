{pkgs, ...}: {
  home.packages = with pkgs; [
    ghostscript
    imagemagick
    markdown-oxide
    mermaid-cli
    tectonic
    typst
  ];
}
