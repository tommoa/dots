{
  config,
  lib,
  pkgs,
  ...
}: let
  addonId = pkgs.arista-browser-extension.addonId;
  signedXpi = pkgs.arista-browser-extension-signed;
  amoApiKeyFile = config.my.secretsPath + "/amo/api-key.age";
  amoApiSecretFile = config.my.secretsPath + "/amo/api-secret.age";
  haveAmoSecrets = builtins.pathExists amoApiKeyFile && builtins.pathExists amoApiSecretFile;
in {
  age.secrets = lib.mkIf haveAmoSecrets {
    amo-api-key = {
      file = amoApiKeyFile;
      path = "${config.home.homeDirectory}/.config/amo/api-key";
      symlink = false;
    };
    amo-api-secret = {
      file = amoApiSecretFile;
      path = "${config.home.homeDirectory}/.config/amo/api-secret";
      symlink = false;
    };
  };

  warnings =
    lib.optional (!haveAmoSecrets) ''
      Arista Browser Extension signing is not configured. Create
      secrets/amo/api-key.age and secrets/amo/api-secret.age with agenix,
      then rebuild the work configuration.
    ''
    ++ lib.optional (signedXpi == null) ''
      The signed Arista Browser Extension is not registered in metadata yet.
      Run `nix run .#update-arista-browser-extension` after configuring AMO credentials.
    '';

  programs.zen-browser.policies.ExtensionSettings =
    {
      "{875ecb07-877d-4c3d-98d5-ffbad1df45f5}" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/cronofy/latest.xpi";
        installation_mode = "force_installed";
      };
    }
    // lib.optionalAttrs (signedXpi != null) {
      "${addonId}" = {
        install_url = "file://${signedXpi}";
        installation_mode = "force_installed";
      };
    };
}
