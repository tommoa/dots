{lib, ...}: {
  services.kanata = {
    enable = true;
    keyboards.laptop = {
      # The layout is shared; each host supplies its own input device paths.
      config = builtins.readFile ../kanata/feral.kbd;
      extraDefCfg = "process-unmapped-keys yes";
    };
  };

  # Kanata must see the host's uinput supplementary group. PrivateUsers masks
  # supplementary host GIDs, so the device remains inaccessible otherwise.
  systemd.services.kanata-laptop.serviceConfig.PrivateUsers = lib.mkForce false;
}
