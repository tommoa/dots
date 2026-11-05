{
  config,
  mailRuntime,
  ...
}: {
  # Work account configuration using home-manager
  # OAuth2 credentials are handled by oauth2-gmail script

  # Work OAuth2 secrets (client credentials only)
  # Note: Refresh token is stored locally per-machine in ~/.local/state/oauth2-gmail/
  # and is obtained via: oauth2-gmail setup work
  age.secrets = {
    work-oauth2-client-id.file = "${config.my.secretsPath}/mail/work-oauth2-client-id.age";
    work-oauth2-client-secret.file = "${config.my.secretsPath}/mail/work-oauth2-client-secret.age";
  };

  accounts.email.accounts.work = {
    address = "toma@arista.com";
    userName = "toma@arista.com";
    realName = "Tom Almeida";

    # OAuth2 authentication via custom script
    passwordCommand = ["${mailRuntime}/bin/oauth2-gmail" "work"];

    # IMAP configuration
    imap = {
      host = "imap.gmail.com";
      port = 993;
      tls.enable = true;
    };

    # SMTP configuration
    smtp = {
      host = "smtp.gmail.com";
      port = 465;
      tls = {
        enable = true;
        useStartTls = false;
      };
    };

    maildir.path = "work";

    mbsync = {
      enable = true;
      create = "both";
      expunge = "both";
      patterns = [
        "*"
        "![Gmail]*"
        "[Gmail]/All Mail"
        "[Gmail]/Drafts"
        "[Gmail]/Sent Mail"
        "[Gmail]/Bin"
        "!Purge*"
      ];
      subFolders = "Verbatim";
      extraConfig = {
        account = {
          AuthMechs = "XOAUTH2";
          # Large uploads can still be draining through TCP after mbsync's last
          # socket callback. Give Gmail time to finish the upload and reply.
          Timeout = 120;
        };
      };
    };

    aerc = {
      enable = true;
      extraAccounts = {
        source = "notmuch://${config.accounts.email.maildirBasePath}/${config.accounts.email.accounts.work.maildir.path}";
        query-map = "~/.config/aerc/work-map";
        folders-sort = "INBOX,Reviews,Escalations,CI,Packages,Archive";
        default = "INBOX";
        outgoing = "msmtp -a work";
        from = "Tom Almeida <toma@arista.com>";
      };
    };

    msmtp = {
      enable = true;
      extraConfig = {
        auth = "xoauth2";
      };
    };

    imapnotify = {
      enable = true;
      boxes = [
        "INBOX"
        "[Gmail]/Sent Mail"
        "Builds"
        "Escalation"
        "Work"
        "Reviews"
        "Packages"
      ];
      onNotify = "account=work ${mailRuntime}/bin/update-mail";
      extraConfig = {
        tls = true;
        tlsOptions = {
          # goimapnotify skips verification if this option is omitted.
          rejectUnauthorized = true;
        };
        xoauth2 = true;
      };
    };
  };

  # Aerc query map
  home.file.".config/aerc/work-map".source = ../config/aerc-work-map;
}
