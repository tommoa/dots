{pkgs, ...}: {
  home.packages = with pkgs; [
    python3Packages.debugpy # DAP adapter for debugging
    pyright # Language server
    uv # Fast Python package/project manager
  ];
}
