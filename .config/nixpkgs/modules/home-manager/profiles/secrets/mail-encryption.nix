{
  config,
  lib,
  pkgs,
  ...
}: let
  primaryFingerprint = "0A03EA4C015A0E1923E407B5BC44284F6BFB03DF";
  encryptedKey = "${config.my.secretsPath}/misc/mail-encryption-subkey.age";
  identity = builtins.head config.age.identityPaths;
  importKey = pkgs.writeShellScript "import-mail-encryption-key" ''
    set -euo pipefail
    ${lib.getExe config.age.package} --decrypt -i ${lib.escapeShellArg identity} ${lib.escapeShellArg encryptedKey} \
      | ${lib.getExe config.programs.gpg.package} --homedir ${lib.escapeShellArg config.programs.gpg.homedir} --batch --quiet --import
    # An imported subkey has a primary-key stub, so GnuPG does not automatically
    # trust our own UID. oauth2-gmail encrypts to that UID without a TTY.
    printf '%s:6:\n' ${lib.escapeShellArg primaryFingerprint} \
      | ${lib.getExe config.programs.gpg.package} --homedir ${lib.escapeShellArg config.programs.gpg.homedir} --batch --quiet --import-ownertrust
  '';
in {
  # oauth2-gmail encrypts each machine's refresh token to this key and later
  # decrypts it locally. Keep the private encryption subkey off the Nix store.
  home.activation.importMailEncryptionKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${importKey}
  '';
}
