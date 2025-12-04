{ config, ... }:

{
  # Gmail account configuration using home-manager
  # OAuth2 credentials are handled by oauth2-gmail script

  # Gmail OAuth2 secrets (client credentials only)
  # Note: Refresh token is stored locally per-machine in ~/.local/state/oauth2-gmail/
  # and is obtained via: oauth2-gmail setup gmail
  age.secrets = {
    gmail-oauth2-client-id.file = "${config.my.secretsPath}/mail/gmail-oauth2-client-id.age";
    gmail-oauth2-client-secret.file = "${config.my.secretsPath}/mail/gmail-oauth2-client-secret.age";
  };

  accounts.email.accounts.gmail = {
    primary = true;
    address = "tommoa256@gmail.com";
    userName = "tommoa256@gmail.com";
    realName = "Tom Almeida";

    # OAuth2 authentication via custom script
    passwordCommand = "${config.home.homeDirectory}/bin/oauth2-gmail gmail";

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

    maildir.path = "gmail";

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
        source = "notmuch://~/.mail/gmail";
        query-map = "~/.config/aerc/notmuch-map";
        folders-sort = "INBOX";
        default = "INBOX";
        outgoing = "msmtp -a gmail";
        from = "Tom Almeida <tommoa256@gmail.com>";
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
      boxes = [ "INBOX" "[Gmail]/Sent Mail" ];
      onNotify = "account=gmail ${config.home.homeDirectory}/bin/update-mail";
      extraConfig = {
        tls = true;
        tlsOptions = {
          rejectUnauthorized = false;
        };
        xoauth2 = true;
      };
    };
  };

  # Aerc query map (notmuch query syntax, shared across accounts)
  home.file.".config/aerc/notmuch-map".source = ./config/aerc-notmuch-map;

  # Notmuch config
  home.file.".config/notmuch/gmail".source = ./config/notmuch-gmail;
}
