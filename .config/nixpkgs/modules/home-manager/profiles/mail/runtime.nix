{
  lib,
  runCommand,
  makeWrapper,
  runtimeShell,
  python3,
  coreutils,
  gnugrep,
  gnused,
  notmuch,
  cacert,
  stdenv,
  getconf,
  util-linux,
  libnotify,
  mbsync,
  gnupg,
}: let
  runtimePath = lib.makeBinPath (
    [coreutils gnugrep gnused notmuch mbsync gnupg]
    ++ lib.optionals stdenv.isDarwin [getconf]
    ++ lib.optionals stdenv.isLinux [util-linux libnotify]
  );
in
  runCommand "mail-runtime" {nativeBuildInputs = [makeWrapper];} ''
    mkdir -p "$out/bin" "$out/libexec/mail" "$out/libexec/notmuch-hooks"
    cp ${./oauth2-gmail.py} "$out/libexec/mail/oauth2-gmail.py"
    cp ${./mail_credentials.py} "$out/libexec/mail/mail_credentials.py"
    cp ${./update-mail.sh} "$out/libexec/mail/update-mail.sh"
    cp ${./hooks/pre-new} "$out/libexec/mail/pre-new.sh"
    cp ${./hooks/post-new} "$out/libexec/mail/post-new.sh"

    wrap_mail() {
      makeWrapper "$1" "$2" --add-flags "$3" \
        --prefix PATH : ${lib.escapeShellArg runtimePath} \
        --suffix PATH : /usr/bin:/bin:/usr/sbin:/sbin \
        --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt
    }

    wrap_mail ${python3}/bin/python3 "$out/bin/oauth2-gmail" "$out/libexec/mail/oauth2-gmail.py"
    wrap_mail ${python3}/bin/python3 "$out/bin/mail-secret" "$out/libexec/mail/mail_credentials.py"
    wrap_mail ${runtimeShell} "$out/bin/update-mail" "$out/libexec/mail/update-mail.sh"
    wrap_mail ${runtimeShell} "$out/libexec/notmuch-hooks/pre-new" "$out/libexec/mail/pre-new.sh"
    wrap_mail ${runtimeShell} "$out/libexec/notmuch-hooks/post-new" "$out/libexec/mail/post-new.sh"
  ''
