{
  config,
  lib,
  pkgs,
  ...
}: let
  signingSubkey = "AF042EB897E56CAE4CA68464DF2AA06F9CEBD259";
  encryptedKey = "${config.my.secretsPath}/misc/git-signing-subkey.age";
  identity = builtins.head config.age.identityPaths;
  importKey = pkgs.writeShellScript "import-git-signing-key" ''
    set -euo pipefail
    ${lib.getExe config.age.package} --decrypt -i ${lib.escapeShellArg identity} ${lib.escapeShellArg encryptedKey} \
      | ${lib.getExe config.programs.gpg.package} --homedir ${lib.escapeShellArg config.programs.gpg.homedir} --batch --quiet --import
  '';
in {
  programs.git.signing = {
    key = "${signingSubkey}!";
    format = "openpgp";
    signByDefault = true;
  };
  programs.git.settings.tag.gpgSign = true;

  # Agenix starts at login after Home Manager activation. Import directly from
  # its encrypted file so signing is ready immediately on Linux and macOS.
  home.activation.importGitSigningKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${importKey}
  '';
}
