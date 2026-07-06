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
    # nixpkgs#528284 marks ghdl available on aarch64-darwin via llvm-jit,
    # but these locked inputs still fail evaluation through gnat-bootstrap13.
    ++ (
      if !pkgs.stdenv.hostPlatform.isDarwin && lib.meta.availableOn pkgs.stdenv.hostPlatform ghdl
      then [ghdl]
      else [nvc]
    );
}
