# Add a common set of fonts for all platforms.

{
  lib,
  config,
  pkgs,
  ...
}:
{
  fonts.packages = with pkgs; [
    dejavu_fonts # Normal fonts.
    fira-code # Monospace.
    # font-awesome # Symbols.
    nerd-fonts.symbols-only # Symbols.
  ];
}
