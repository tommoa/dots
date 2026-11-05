{
  config,
  mailRuntime,
  ...
}: let
  maildirPath = "${config.accounts.email.maildirBasePath}/${config.accounts.email.accounts.shared.maildir.path}";
in {
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
    passwordCommand = ["${mailRuntime}/bin/oauth2-gmail" "shared"];

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

    folders = {
      inbox = "Inbox";
      # Sent is a query folder, so aerc can't use it as a copy-to destination.
      sent = null;
      drafts = "[Gmail]/Drafts";
    };

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
        "[Gmail]/Trash"
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
        check-mail-cmd = "account=shared exec ${mailRuntime}/bin/update-mail";
        check-mail-timeout = "30m";
        source = "notmuch://${maildirPath}";
        # aerc needs a Maildir to save drafts, even though we read through Notmuch.
        maildir-store = maildirPath;
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
      onNotify = "account=shared ${mailRuntime}/bin/update-mail";
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

  # Aerc query map for shared account (includes RSVP folder)
  home.file.".config/aerc/shared-map".source = ../config/aerc-shared-map;
}
