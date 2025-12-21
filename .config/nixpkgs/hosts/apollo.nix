{pkgs, ...}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

  imports = [
    ../modules/darwin/profiles/base.nix
    ../modules/darwin/profiles/desktop.nix
  ];

  system.primaryUser = "toma";
  users.users.toma = {
    description = "Tom Hill Almeida";
    home = "/Users/toma";
    shell = pkgs.zsh;
    packages = with pkgs; [
      chatgpt
    ];
  };
}
