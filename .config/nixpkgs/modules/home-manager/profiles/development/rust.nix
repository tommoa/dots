{pkgs, ...}: {
  # rustup manages the Rust toolchain including rust-analyzer
  home.packages = with pkgs; [
    rustup
  ];
}
