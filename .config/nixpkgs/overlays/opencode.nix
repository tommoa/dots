inputs: self: super: {
  opencode = inputs.opencode.packages.${super.stdenv.hostPlatform.system}.default;
}
