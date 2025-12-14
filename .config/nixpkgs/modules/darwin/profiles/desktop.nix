{ pkgs, ... }:

{
  services.yabai = {
    enable = true;
    package = pkgs.yabai;
    enableScriptingAddition = true;

    config = {
      # Global settings
      mouse_follows_focus = "on";
      focus_follows_mouse = "autoraise";
      window_placement = "second_child";
      window_shadow = "on";
      window_opacity = "off";
      window_opacity_duration = 0.0;
      active_window_opacity = 1.0;
      normal_window_opacity = 0.90;
      insert_feedback_color = "0xffd75f5f";
      split_ratio = 0.50;
      auto_balance = "off";
      mouse_modifier = "cmd";
      mouse_action1 = "move";
      mouse_action2 = "resize";
      mouse_drop_action = "swap";

      # General space
      layout = "bsp";
      top_padding = 12;
      bottom_padding = 12;
      left_padding = 12;
      right_padding = 12;
      window_gap = 06;
    };

    extraConfig = ''
      yabai -m rule --add app='System Settings' manage=off
      yabai -m rule --add app='Obsidian' space=5
      yabai -m rule --add app='Discord' space=4
      yabai -m rule --add app='WhatsApp' space=4
      yabai -m rule --add app='Messenger' space=4
      yabai -m rule --add app='Messages' space=4
      yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"
      yabai -m signal --add app='^Ghostty$' event=window_created action='yabai -m space --layout bsp'
      yabai -m signal --add app='^Ghostty$' event=window_destroyed action='yabai -m space --layout bsp'
      sudo yabai --load-sa
    '';
  };

  services.skhd = {
    enable = true;
    package = pkgs.skhd;
  };
}
