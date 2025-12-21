{config, ...}: {
  # Shared account configuration using home-manager
  # OAuth2 credentials are handled by oauth2-gmail script

  # Shared OAuth2 secrets (client credentials only)
  # Note: Refresh token is stored locally per-machine in ~/.local/state/oauth2-gmail/
  # and is obtained via: oauth2-gmail setup shared
  age.secrets = {
    shared-oauth2-client-id.file = "${config.my.secretsPath}/mail/shared-oauth2-client-id.age";
    shared-oauth2-client-secret.file = "${config.my.secretsPath}/mail/shared-oauth2-client-secret.age";
  };

  accounts.email.accounts.shared = {
    primary = false;
    address = "emilyandtom.almeida@gmail.com";
    userName = "emilyandtom.almeida@gmail.com";
    realName = "Emily and Tom Almeida";

    # OAuth2 authentication via custom script
    passwordCommand = "${config.home.homeDirectory}/bin/oauth2-gmail shared";

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

    maildir.path = "shared";

    mbsync = {
      enable = true;
      create = "both";
      expunge = "both";
      patterns = [
        "!*"
        "![Gmail]*"
        "[Gmail]/Drafts"
        "[Gmail]/Sent Mail"
        "[Gmail]/All Mail"
        "[Gmail]/Bin"
        "INBOX"
        "RSVP"
      ];
      subFolders = "Verbatim";
      extraConfig = {
        account = {
          AuthMechs = "XOAUTH2";
        };
      };
    };

    aerc = {
      enable = true;
      extraAccounts = {
        source = "notmuch://~/.mail/shared";
        query-map = "~/.config/aerc/shared-map";
        folders-sort = "INBOX";
        default = "INBOX";
        outgoing = "msmtp -a shared";
        from = "Emily and Tom Almeida <emilyandtom.almeida@gmail.com>";
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
        "RSVP"
      ];
      onNotify = "account=shared ${config.home.homeDirectory}/bin/update-mail";
      extraConfig = {
        tls = true;
        tlsOptions = {
          rejectUnauthorized = false;
        };
        xoauth2 = true;
      };
    };
  };

  # Aerc query map for shared account (includes RSVP folder)
  home.file.".config/aerc/shared-map".source = ../config/aerc-shared-map;

  # Notmuch config
  home.file.".config/notmuch/shared".source = ../config/notmuch-shared;
}
