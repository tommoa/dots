{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.yamaha-audio;
in {
  options.services.yamaha-audio = {
    enable = lib.mkEnableOption "Yamaha AG audio controller support";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.wine
      (pkgs.callPackage ../../packages/yamaha-ag-controller {})
      pkgs.usbutils
    ];

    # USB device permissions
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="0499", ATTR{idProduct}=="1757", MODE="0666"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0499", ATTRS{idProduct}=="1757", MODE="0666"
    '';
  };
}
