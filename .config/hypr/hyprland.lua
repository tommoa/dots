----------------
-- Monitors
----------------

-- HDR/VRR enabled display: DP-3 at 2560x1440@165Hz.
hl.monitor({
    output = "DP-3",
    mode = "2560x1440@165",
    position = "auto",
    scale = "auto",
    bitdepth = 10,
    -- cm = "hdr",
    vrr = 2,
    sdrbrightness = 1.2,
    sdrsaturation = 1.1,
})

hl.monitor({
    output = "",
    mode = "highrr",
    position = "auto",
    scale = "auto",
})

----------------
-- Startup
----------------

local sleep = "swaylock -f"

hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm app -- waybar")
    hl.exec_cmd("uwsm app -- swaybg -i ~/.config/sway/background.jpg -m fill")
    hl.exec_cmd("uwsm app -- swayidle -w timeout 300 " .. sleep .. " timeout 600 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on' before-sleep " .. sleep)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'Pop-dark'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface icon-theme 'Pop'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme 'Pop'")
end)

----------------
-- Settings
----------------

hl.config({
    general = {
        gaps_in = 2,
        gaps_out = 2,
        border_size = 2,
        col = {
            active_border = 0xfff07178,
            inactive_border = 0x8f676e95,
        },
        resize_on_border = false,
        hover_icon_on_border = true,
        layout = "dwindle",
        allow_tearing = true,
    },

    decoration = {
        rounding = 0,
        blur = {
            enabled = false,
            size = 3,
            passes = 1,
            vibrancy = 0.16,
        },
        shadow = {
            enabled = false,
            range = 4,
            render_power = 3,
            color = 0xee1a1a1a,
        },
    },

    animations = {
        enabled = false,
    },

    input = {
        kb_layout = "us",
        kb_variant = "colemak",
        kb_model = "",
        kb_options = "caps:escape",
        kb_rules = "",

        follow_mouse = 1,
        float_switch_override_focus = 2,

        natural_scroll = true,
        sensitivity = 0.0,
        accel_profile = "flat",
        force_no_accel = true,

        touchpad = {
            disable_while_typing = true,
            tap_to_click = true,
            drag_lock = false,
            scroll_factor = 1.0,
        },
    },

    gestures = {
        workspace_swipe_distance = 300,
        workspace_swipe_cancel_ratio = 0.5,
        workspace_swipe_create_new = true,
        workspace_swipe_forever = false,
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        focus_on_activate = true,
    },

    debug = {
        vfr = true,
    },

    render = {
        cm_enabled = true,
        cm_auto_hdr = 1,
        cm_fs_passthrough = 1,
        direct_scanout = true,
    },

    quirks = {
        prefer_hdr = 1,
    },

    cursor = {
        sync_gsettings_theme = true,
    },
})

hl.env("XCURSOR_THEME", "Pop")
hl.env("DXVK_HDR", "1")
hl.env("ENABLE_HDR_WSI", "1")

----------------
-- Keybindings
----------------

local mod = "SUPER"
local left = "H"
local down = "N"
local up = "E"
local right = "I"

local osdclient = [[swayosd-client --monitor "$(hyprctl monitors -j | jq -r '.[] | select(.focused == true).name')"]]

hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + return", hl.dsp.exec_cmd("uwsm app -- ghostty"))
hl.bind(mod .. " + P", hl.dsp.exec_cmd("uwsm app -- wofi -diImSdrun"))

-- Move focus with Colemak vim keys.
hl.bind(mod .. " + " .. left, hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + " .. down, hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + " .. up, hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + " .. right, hl.dsp.focus({ direction = "right" }))

-- Move windows with Colemak vim keys.
hl.bind(mod .. " + SHIFT + " .. left, hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. " + SHIFT + " .. down, hl.dsp.window.move({ direction = "down" }))
hl.bind(mod .. " + SHIFT + " .. up, hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + SHIFT + " .. right, hl.dsp.window.move({ direction = "right" }))

-- Laptop multimedia keys for volume and LCD brightness.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume raise"), { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume lower"), { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(osdclient .. " --output-volume mute-toggle"), { locked = true, repeating = true, description = "Mute" })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(osdclient .. " --input-volume mute-toggle"), { locked = true, repeating = true, description = "Mute microphone" })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(osdclient .. " --brightness raise"), { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(osdclient .. " --brightness lower"), { locked = true, repeating = true, description = "Brightness down" })

-- Precise 1% multimedia adjustments with Alt.
hl.bind("ALT + XF86AudioRaiseVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume +1"), { locked = true, repeating = true, description = "Volume up precise" })
hl.bind("ALT + XF86AudioLowerVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume -1"), { locked = true, repeating = true, description = "Volume down precise" })
hl.bind("ALT + XF86MonBrightnessUp", hl.dsp.exec_cmd(osdclient .. " --brightness +1"), { locked = true, repeating = true, description = "Brightness up precise" })
hl.bind("ALT + XF86MonBrightnessDown", hl.dsp.exec_cmd(osdclient .. " --brightness -1"), { locked = true, repeating = true, description = "Brightness down precise" })

-- Requires playerctl.
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(osdclient .. " --playerctl next"), { locked = true, description = "Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(osdclient .. " --playerctl play-pause"), { locked = true, description = "Pause" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(osdclient .. " --playerctl play-pause"), { locked = true, description = "Play" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(osdclient .. " --playerctl previous"), { locked = true, description = "Previous track" })

for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, silent = true }))
end

hl.bind(mod .. " + l", hl.dsp.focus({ workspace = "-1" }))
hl.bind(mod .. " + u", hl.dsp.focus({ workspace = "+1" }))
hl.bind(mod .. " + y", hl.dsp.focus({ workspace = "previous" }))
hl.bind(mod .. " + TAB", hl.dsp.focus({ workspace = "previous" }))

hl.bind(mod .. " + SHIFT + l", hl.dsp.window.move({ workspace = "-1", silent = true }))
hl.bind(mod .. " + SHIFT + u", hl.dsp.window.move({ workspace = "+1", silent = true }))
hl.bind(mod .. " + SHIFT + y", hl.dsp.window.move({ workspace = "previous", silent = true }))

-- Scroll through existing workspaces with mod + scroll.
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mod + mouse click.
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

----------------
-- Window rules
----------------

hl.window_rule({ name = "chatgpt-workspace", match = { class = "codex-desktop" }, workspace = "3 silent" })
hl.window_rule({ name = "discord-workspace", match = { class = "discord" }, workspace = "4 silent" })
hl.window_rule({ name = "obsidian-workspace", match = { class = "obsidian" }, workspace = "5 silent" })
hl.window_rule({ name = "steam-workspace", match = { class = "steam" }, workspace = "6 silent" })

hl.window_rule({ name = "cs2-workspace", match = { class = "^(cs2)$" }, workspace = "7 silent", immediate = true })
hl.window_rule({ name = "gamescope-workspace", match = { class = "^(gamescope)$" }, workspace = "7 silent", immediate = true })
hl.window_rule({ name = "deadlock-workspace", match = { class = "^(deadlock)$" }, workspace = "7 silent", immediate = true })
hl.window_rule({ name = "aoe-workspace", match = { title = "Age of Empires .*" }, workspace = "7 silent", immediate = true })

-- Picture-in-picture overlays.
hl.window_rule({ name = "tag-pip", match = { title = "(Picture.?in.?[Pp]icture)" }, tag = "+pip" })
hl.window_rule({ name = "float-pip", match = { tag = "pip" }, float = true })
hl.window_rule({ name = "pin-pip", match = { tag = "pip" }, pin = true })
hl.window_rule({ name = "size-pip", match = { tag = "pip" }, size = "600 338" })
hl.window_rule({ name = "keepaspectratio-pip", match = { tag = "pip" }, keep_aspect_ratio = true })
hl.window_rule({ name = "noborder-pip", match = { tag = "pip" }, border_size = 0 })
hl.window_rule({ name = "opacity-pip", match = { tag = "pip" }, opacity = "1 1" })
hl.window_rule({ name = "move-pip", match = { tag = "pip" }, move = "100%-w-40 4%" })

-- Floating windows.
hl.window_rule({ name = "float-floating-window", match = { tag = "floating-window" }, float = true })
hl.window_rule({ name = "center-floating-window", match = { tag = "floating-window" }, center = true })
hl.window_rule({ name = "size-floating-window", match = { tag = "floating-window" }, size = "1200 800" })
hl.window_rule({ name = "tag-floating-window", match = { class = "(org\\.blueman\\.Manager|.*pavucontrol|TUI\\.float)" }, tag = "+floating-window" })
