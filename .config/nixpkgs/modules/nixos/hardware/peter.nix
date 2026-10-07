# Hardware and filesystem configuration for peter.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" "sdhci_pci"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # AHCI runtime suspend triggers USB controller failures on this ThinkPad E485,
  # disconnecting the YubiKey, camera and Bluetooth. Keeping AHCI awake restored
  # USB, so disable runtime PM for its ports and PCI controller (06:00.0).
  # https://linrunner.de/tlp/faq/usb.html#usb-devices-not-working-on-battery-power
  services.tlp.settings = {
    AHCI_RUNTIME_PM_ON_BAT = "on";
    RUNTIME_PM_DISABLE = "06:00.0";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/2ae3c985-a150-47fc-8953-817bbf6cf0e0";
    fsType = "btrfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2CA5-B958";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  swapDevices = [
    {device = "/dev/disk/by-uuid/ed45594d-13b2-49c6-a9ad-e7346069794c";}
  ];
  boot.resumeDevice = "/dev/disk/by-uuid/ed45594d-13b2-49c6-a9ad-e7346069794c";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
