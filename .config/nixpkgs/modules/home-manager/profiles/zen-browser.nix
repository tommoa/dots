{
  config,
  pkgs,
  lib,
  ...
}: {
  # Zen needs to update profiles.ini at runtime. Home Manager normally leaves
  # this generated file as a read-only store symlink, so replace that symlink
  # with an equivalent writable file after each activation on macOS.
  home.file = lib.mkIf pkgs.stdenv.isDarwin {
    "${config.home.homeDirectory}/Library/Application Support/Zen/profiles.ini".force = true;
  };

  home.activation.zenUnlockProfilesIni = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter ["linkGeneration"] ''
      profiles_ini="${config.home.homeDirectory}/Library/Application Support/Zen/profiles.ini"
      if [ -L "$profiles_ini" ]; then
        profiles_source="$(readlink "$profiles_ini")"
        profiles_tmp="$(mktemp "$profiles_ini.XXXXXX")"
        cp "$profiles_source" "$profiles_tmp"
        chmod 0644 "$profiles_tmp"
        mv -f "$profiles_tmp" "$profiles_ini"
      fi
    ''
  );

  programs.zen-browser = {
    enable = true;
    profiles.default = {
      name = "default";
      path = "default";
      # Zen and Multi-Account Containers Sync own containers and site assignments.
      # Keep spaces browser-owned too: their container IDs are profile-local.
      search = {
        force = true;
        default = "ddg";
        privateDefault = "ddg";
      };
      settings = {
        "browser.contentblocking.category" = "standard";
        "browser.toolbars.bookmarks.visibility" = "always";
        "browser.startup.page" = 3;
        "browser.newtabpage.activity-stream.section.highlights.rows" = 2;
        "browser.newtabpage.activity-stream.topSitesRows" = 2;
        "privacy.donottrackheader.enabled" = true;
        "privacy.userContext.enabled" = true;
        "privacy.userContext.ui.enabled" = true;
        "sidebar.position_start" = false;
        "sidebar.visibility" = "hide-on-close";
        "widget.macos.sidebar-blend-mode.behind-window" = false;
        "zen.tabs.vertical" = true;
        "zen.tabs.vertical.right-side" = true;
        "zen.theme.content-element-separation" = 2;
        "zen.urlbar.behavior" = "float";
        "zen.view.compact.enable-at-startup" = true;
        "zen.view.compact.hide-toolbar" = true;
        "zen.view.compact.should-enable-at-startup" = true;
        "zen.widget.macos.window-vibrancy" = false;
        "zen.workspaces.continue-where-left-off" = true;
      };
    };
    policies = let
      mkExtensionSettings = builtins.mapAttrs (
        _: pluginId: {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/${pluginId}/latest.xpi";
          installation_mode = "force_installed";
        }
      );
    in {
      ExtensionSettings = mkExtensionSettings {
        "uBlock0@raymondhill.net" = "ublock-origin";
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
        "@testpilot-containers" = "multi-account-containers";
        "@contain-facebook" = "facebook-container";
        "{04188724-64d3-497b-a4fd-7caffe6eab29}" = "rust-search-extension";
        "enhancerforyoutube@maximerf.addons.mozilla.org" = "enhancer-for-youtube";
        "{c49b13b1-5dee-4345-925e-0c793377e3fa}" = "youtube-enhancer-vc";
      };
    };
    nativeMessagingHosts = lib.optionals pkgs.stdenv.isLinux [pkgs.bitwarden-desktop];
  };
}
