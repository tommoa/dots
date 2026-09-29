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
    darwin.packageMode = "wrapped";
    profiles.default = {
      name = "default";
      path = "default";
      containersForce = true;
      containers = {
        # Home Manager cannot preserve Firefox's localized built-in names, so
        # keep their stable IDs and spell the current English names explicitly.
        personal = {
          id = 1;
          name = "Personal";
          color = "blue";
          icon = "fingerprint";
        };
        work = {
          id = 2;
          name = "Work";
          color = "orange";
          icon = "briefcase";
        };
        banking = {
          id = 3;
          name = "Banking";
          color = "green";
          icon = "dollar";
        };
        shopping = {
          id = 4;
          name = "Shopping";
          color = "pink";
          icon = "cart";
        };
        facebook = {
          id = 6;
          name = "Facebook";
          # Zen serializes this palette entry as "gray".
          color = "toolbar";
          icon = "fence";
        };
        dev = {
          id = 7;
          name = "dev";
          color = "blue";
          icon = "briefcase";
        };
      };
      # Upsert these stable space IDs without deleting spaces created locally.
      spacesForce = false;
      spaces = {
        personal = {
          id = "be813648-6f57-4cbd-af7e-b5d554d7dc81";
          name = "Space";
          position = 1000;
          theme = {
            colors = [
              {
                red = 176;
                green = 222;
                blue = 255;
                lightness = 50;
                position = {
                  x = 138;
                  y = 138;
                };
              }
            ];
            opacity = 0.636;
          };
        };
        work = {
          id = "4ec84f17-feca-4368-bae9-907955981321";
          name = "Work";
          position = 2000;
          icon = "🧳";
          container = 2;
          theme = {
            colors = [
              {
                red = 239;
                green = 136;
                blue = 118;
                lightness = 70;
                position = {
                  x = 220;
                  y = 187;
                };
                type = "explicit-lightness";
              }
            ];
            opacity = 0.25;
          };
        };
        ai-lsp = {
          id = "4245314b-e8b2-4510-a4bc-f3a5c7e09c9d";
          name = "ai-lsp";
          position = 3000;
          icon = "✨️";
          container = 7;
        };
        programming = {
          id = "9d0c74c9-3c38-46c6-bac5-226ec51d2425";
          name = "Programming";
          position = 4000;
          icon = "🎹";
          container = 7;
          theme = {
            colors = [
              {
                red = 71;
                green = 235;
                blue = 174;
                lightness = 60;
                position = {
                  x = 147;
                  y = 195;
                };
                type = "explicit-lightness";
              }
            ];
            opacity = 0.549;
          };
        };
        keyboards = {
          id = "d41fe10e-ae97-413b-9e27-e82c5280b021";
          name = "Keyboards";
          position = 5000;
          icon = "⌨️";
          container = 1;
          theme.colors = [
            {
              red = 230;
              green = 178;
              blue = 223;
              lightness = 80;
              position = {
                x = 236;
                y = 111;
              };
              type = "explicit-lightness";
            }
          ];
        };
      };
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
    nativeMessagingHosts =
      [
        (lib.mkIf pkgs.stdenv.isLinux pkgs.firefoxpwa)
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [pkgs.bitwarden-desktop];
  };
}
