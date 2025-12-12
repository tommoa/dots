inputs: self: super:

{
  unstable = import inputs.nixpkgs-unstable { inherit (super) system; };
}
// (import ./yabai.nix self super)
// (import ./whatsapp.nix self super)
// (import ./opencode.nix self super)
