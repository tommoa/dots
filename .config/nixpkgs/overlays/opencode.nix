inputs: self: super: {
  opencode = inputs.opencode.packages.${super.system}.default;
}
