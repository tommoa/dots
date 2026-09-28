{pkgs, ...}: let
  setPowerProfileFromAc = pkgs.writeShellApplication {
    name = "set-power-profile-from-ac";
    runtimeInputs = [pkgs.coreutils pkgs.power-profiles-daemon];
    text = ''
      profile=power-saver

      for supply in /sys/class/power_supply/*; do
        [ -r "$supply/type" ] || continue
        [ -r "$supply/online" ] || continue
        [ "$(cat "$supply/type")" = Mains ] || continue
        if [ "$(cat "$supply/online")" = 1 ]; then
          profile=balanced
          break
        fi
      done

      powerprofilesctl set "$profile"
    '';
  };
in {
  # Expose standard balanced, performance, and power-saver profiles.
  services.power-profiles-daemon.enable = true;

  # Let LAVD follow this laptop's active power profile.
  services.scx.extraArgs = ["--autopower"];

  # Choose a profile from the live AC state at boot and on charger changes.
  # LAVD's --autopower then maps that profile to its own scheduler power mode.
  systemd.services.power-profile-from-ac = {
    description = "Select power profile from AC power state";
    # power-profiles-daemon starts after multi-user.target, so this must not
    # also hold up that target while waiting for the daemon.
    wantedBy = ["graphical.target"];
    after = ["power-profiles-daemon.service"];
    requires = ["power-profiles-daemon.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${setPowerProfileFromAc}/bin/set-power-profile-from-ac";
    };
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_TYPE}=="Mains", ACTION=="change", RUN+="${pkgs.systemd}/bin/systemctl --no-block start power-profile-from-ac.service"
  '';
}
