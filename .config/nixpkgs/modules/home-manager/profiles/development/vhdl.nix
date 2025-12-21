{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs;
    [
      gtkwave # Waveform viewer
      vhdl-ls # Language server
    ]
    # ghdl doesn't support all platforms (e.g. aarch64-darwin), use nvc as fallback
    ++ (
      if lib.meta.availableOn pkgs.stdenv.hostPlatform ghdl
      then [ghdl]
      else [nvc]
    );
}
