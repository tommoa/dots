{
  lib,
  bluetoothEnabled,
  brightnessEnabled,
  powerProfilesEnabled,
}: {
  name = "devices";
  name_pretty = "Devices";
  icon = "preferences-system";

  entries =
    [
      {
        text = "Audio settings";
        actions.open = "uwsm app -- pavucontrol";
        icon = "audio-volume-high-symbolic";
      }
      {
        text = "Network settings";
        actions.open = "uwsm app -- ghostty --class=TUI.float -e nmtui";
        icon = "network-wireless";
      }
    ]
    ++ lib.optional bluetoothEnabled {
      text = "Bluetooth settings";
      actions.open = "uwsm app -- blueman-manager";
      icon = "bluetooth";
    }
    ++ lib.optionals powerProfilesEnabled [
      {
        text = "Power profile: balanced";
        actions.set = "powerprofilesctl set balanced";
        icon = "power-profile-balanced-symbolic";
      }
      {
        text = "Power profile: power saver";
        actions.set = "powerprofilesctl set power-saver";
        icon = "power-profile-power-saver-symbolic";
      }
      {
        text = "Power profile: performance";
        actions.set = "powerprofilesctl set performance";
        icon = "power-profile-performance-symbolic";
      }
    ]
    ++ lib.optionals brightnessEnabled [
      {
        text = "Increase brightness by 10%";
        actions.set = "brightnessctl set 10%+";
        icon = "display-brightness-high-symbolic";
      }
      {
        text = "Increase brightness by 25%";
        actions.set = "brightnessctl set 25%+";
        icon = "display-brightness-high-symbolic";
      }
      {
        text = "Decrease brightness by 10%";
        actions.set = "brightnessctl set 10%-";
        icon = "display-brightness-low-symbolic";
      }
      {
        text = "Decrease brightness by 25%";
        actions.set = "brightnessctl set 25%-";
        icon = "display-brightness-low-symbolic";
      }
    ];
}
