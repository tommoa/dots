{
  lib,
  pkgs,
  batteryEnabled ? false,
  powerProfilesEnabled ? false,
}:
{
  "reload_style_on_change" = true;
  "layer" = "top";
  "position" = "top";
  "height" = 30;
  "spacing" = 0;
  "modules-left" = [
    "hyprland/workspaces"
    "hyprland/submap"
  ];
  "modules-center" = [
    "clock"
    "custom/recording"
  ];
  "modules-right" =
    [
      "tray"
      "idle_inhibitor"
      "wireplumber"
      "bluetooth"
      "network"
      "memory"
      "cpu"
      "temperature"
    ]
    ++ lib.optional powerProfilesEnabled "power-profiles-daemon"
    ++ lib.optional batteryEnabled "battery"
    ++ [
      "group/group-power"
    ];
  "hyprland/workspaces" = {
    "on-click" = "activate";
    "format" = "{icon}";
    "sort-by" = "id";
    "format-icons" = {
      "default" = "";
      "1" = "1";
      "2" = "2";
      "3" = "3";
      "4" = "4";
      "5" = "5";
      "6" = "6";
      "7" = "7";
      "8" = "8";
      "9" = "9";
    };
  };
  "hyprland/submap" = {
    "format" = "<span style=\"italic\">{}</span>";
  };
  "idle_inhibitor" = {
    "format" = "{icon}";
    "format-icons" = {
      "activated" = "";
      "deactivated" = "";
    };
    "signal" = 8;
    "tooltip" = false;
  };
  "custom/recording" = {
    "exec" = pkgs.writeShellScript "waybar-screen-recording" ''
      if ${pkgs.procps}/bin/pgrep -x wf-recorder >/dev/null; then
        printf '%s\n' '{"text":" REC","class":"recording","tooltip":"Screen recording in progress"}'
      else
        printf '%s\n' '{"text":"","class":"inactive"}'
      fi
    '';
    "return-type" = "json";
    "interval" = 1;
    "hide-empty-text" = true;
  };
  "clock" = {
    "format" = "{:%A %d %H:%M}";
    "format-alt" = "{:%a %Y-%m-%d}";
    "tooltip" = false;
  };
  "temperature" = {
    "input-filename" = "temp1_input";
    "critical-threshold" = 80;
    "format" = "{icon}";
    "format-icons" = [
      ""
      ""
      ""
      ""
    ];
    "format-critical" = "";
    "on-click" = "${pkgs.uwsm}/bin/uwsm app -- ${pkgs.ghostty}/bin/ghostty --class=TUI.float -e ${pkgs.btop}/bin/btop";
    "interval" = 1;
  };
  "bluetooth" = {
    "format" = "";
    "format-disabled" = "󰂲";
    "format-connected" = "";
    "tooltip-format" = "Devices connected: {num_connections}";
    "on-click" = "${pkgs.blueman}/bin/blueman-manager";
  };
  "network" = {
    "format-wifi" = "{icon}";
    "format-icons" = [
      "󰤯"
      "󰤟"
      "󰤢"
      "󰤥"
      "󰤨"
    ];
    "format" = "{icon}";
    "format-ethernet" = "󰈀";
    "format-disconnected" = "󰖪";
    "tooltip-format-wifi" = "{essid} ({frequency} GHz)\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
    "tooltip-format-ethernet" = "{ifname}\n⇣{bandwidthDownBytes}  ⇡{bandwidthUpBytes}";
    "tooltip-format-disconnected" = "Disconnected";
    "interval" = 3;
    "spacing" = 1;
    "on-click" = "${pkgs.uwsm}/bin/uwsm app -- ${pkgs.ghostty}/bin/ghostty --class=TUI.float -e ${pkgs.networkmanager}/bin/nmtui";
  };
  "wireplumber" = {
    "format" = "{icon}";
    "format-bluetooth" = "{icon}";
    "format-bluetooth-muted" = "󰝟 {icon}";
    "format-muted" = "󰝟";
    "format-source" = "{volume}% ";
    "format-source-muted" = "";
    "format-icons" = {
      "headphones" = "";
      "handsfree" = "";
      "headset" = "";
      "phone" = "";
      "portable" = "";
      "car" = "";
      "default" = [
        ""
        ""
        ""
      ];
    };
    "on-click" = "${pkgs.pavucontrol}/bin/pavucontrol";
    "scroll-step" = 5;
    "tooltip-format" = "{volume}% ({node_name})";
  };
  "tray" = {
    "icon-size" = 18;
    "spacing" = 10;
  };
  "cpu" = {
    "interval" = 1;
    "format" = "{icon0}{icon1}{icon2}{icon3} {usage:>2}%";
    "format-icons" = [
      "▁"
      "▂"
      "▃"
      "▄"
      "▅"
      "▆"
      "▇"
      "█"
    ];
    "on-click" = "${pkgs.uwsm}/bin/uwsm app -- ${pkgs.ghostty}/bin/ghostty --class=TUI.float -e ${pkgs.btop}/bin/btop";
  };
  "memory" = {
    "format" = "{used:0.1f}G/{total:0.1f}G";
    "interval" = 5;
    "on-click" = "${pkgs.uwsm}/bin/uwsm app -- ${pkgs.ghostty}/bin/ghostty --class=TUI.float -e ${pkgs.btop}/bin/btop";
  };
  "group/group-power" = {
    "orientation" = "inherit";
    "drawer" = {
      "transition-duration" = 500;
      "children-class" = "not-power";
      "transition-left-to-right" = false;
    };
    "modules" = [
      "custom/power"
      "custom/quit"
      "custom/lock"
      "custom/reboot"
    ];
  };
  "custom/quit" = {
    "format" = "󰗼";
    "tooltip" = false;
    "on-click" = "${pkgs.hyprland}/bin/hyprctl dispatch exit";
  };
  "custom/lock" = {
    "format" = "󰍁";
    "tooltip" = false;
    "on-click" = "${pkgs.swaylock}/bin/swaylock";
  };
  "custom/reboot" = {
    "format" = "󰜉";
    "tooltip" = false;
    "on-click" = "${pkgs.systemd}/bin/systemctl reboot";
  };
  "custom/power" = {
    "format" = "";
    "tooltip" = false;
    "on-click" = "${pkgs.systemd}/bin/systemctl poweroff";
  };
}
// lib.optionalAttrs batteryEnabled {
  battery = {
    states = {
      warning = 30;
      critical = 15;
    };
    format = "{icon}";
    "format-discharging" = "{icon}";
    "format-charging" = "{icon}";
    "format-plugged" = "";
    "format-icons" = {
      charging = [
        "󰢜"
        "󰂆"
        "󰂇"
        "󰂈"
        "󰢝"
        "󰂉"
        "󰢞"
        "󰂊"
        "󰂋"
        "󰂅"
      ];
      default = [
        "󰁺"
        "󰁻"
        "󰁼"
        "󰁽"
        "󰁾"
        "󰁿"
        "󰂀"
        "󰂁"
        "󰂂"
        "󰁹"
      ];
    };
    "format-full" = "󰂅";
    "tooltip-format-discharging" = "{power:>1.0f}W↓ {capacity}% · {time}";
    "tooltip-format-charging" = "{power:>1.0f}W↑ {capacity}% · {time}";
    interval = 5;
  };
}
// lib.optionalAttrs powerProfilesEnabled {
  "power-profiles-daemon" = {
    format = "{icon}";
    # Waybar 0.15 exposes one driver field, without separate CPU/platform fields.
    "tooltip-format" = "Power profile: {profile}\nDriver: {driver}";
    "format-icons" = {
      default = "";
      performance = "";
      balanced = "";
      "power-saver" = "";
    };
  };
}
