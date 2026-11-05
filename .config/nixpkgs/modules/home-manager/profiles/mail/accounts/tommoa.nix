{
  config,
  mailRuntime,
  ...
}: {
  # tommoa (iCloud) account configuration using home-manager
  # Password is read from agenix secret via passwordCommand

  # tommoa password secret
  age.secrets = {
    tommoa-password.file = "${config.my.secretsPath}/mail/tommoa-password.age";
  };

  accounts.email.accounts.tommoa = {
    address = "tom@tommoa.me";
    userName = "tommoa256";
    realName = "Tom Almeida";

    # Password from agenix secret
    passwordCommand = ["${mailRuntime}/bin/mail-secret" "tommoa-password"];

    # IMAP configuration for iCloud
    imap = {
      host = "imap.mail.me.com";
      port = 993;
      tls.enable = true;
    };

    # SMTP configuration for iCloud
    smtp = {
      host = "smtp.mail.me.com";
      port = 587;
      tls = {
        enable = true;
        useStartTls = true;
      };
    };

    maildir.path = "tommoa";

    mbsync = {
      enable = true;
      create = "both";
      expunge = "both";
      patterns = ["*"];
      subFolders = "Verbatim";
      extraConfig = {
        account = {
          Timeout = 0;
          AuthMechs = "LOGIN";
        };
        channel = {
          CopyArrivalDate = true;
        };
      };
    };

    aerc = {
      enable = true;
      extraAccounts = {
        source = "notmuch://${config.accounts.email.maildirBasePath}/${config.accounts.email.accounts.tommoa.maildir.path}";
        query-map = "~/.config/aerc/notmuch-map";
        folders-sort = "INBOX";
        default = "INBOX";
        outgoing = "msmtp -a tommoa";
        from = "Tom Almeida <tom@tommoa.me>";
      };
    };

    msmtp = {
      enable = true;
    };

    imapnotify = {
      enable = true;
      boxes = [
        "INBOX"
        "Sent Messages"
      ];
      onNotify = "account=tommoa ${mailRuntime}/bin/update-mail";
      extraConfig = {
        tls = true;
        tlsOptions = {
          # goimapnotify skips verification if this option is omitted.
          rejectUnauthorized = true;
        };
      };
    };
  };
}
