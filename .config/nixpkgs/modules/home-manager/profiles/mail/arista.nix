{ config, ... }:

{
  # Arista (work) account configuration using home-manager
  # OAuth2 credentials are handled by oauth2-gmail script

  # Arista OAuth2 secrets (client credentials only)
  # Note: Refresh token is stored locally per-machine in ~/.local/state/oauth2-gmail/
  # and is obtained via: oauth2-gmail setup arista
  age.secrets = {
    arista-oauth2-client-id.file = "${config.my.secretsPath}/mail/arista-oauth2-client-id.age";
    arista-oauth2-client-secret.file = "${config.my.secretsPath}/mail/arista-oauth2-client-secret.age";
  };

  accounts.email.accounts.arista = {
    address = "toma@arista.com";
    userName = "toma@arista.com";
    realName = "Tom Almeida";

    # OAuth2 authentication via custom script
    passwordCommand = "${config.home.homeDirectory}/bin/oauth2-gmail arista";

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

    maildir.path = "arista";

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
        };
      };
    };

    aerc = {
      enable = true;
      extraAccounts = {
        source = "notmuch://~/.mail/arista";
        query-map = "~/.config/aerc/work-map";
        folders-sort = "INBOX,Reviews,Escalations,CI,Packages,Archive";
        default = "INBOX";
        outgoing = "msmtp -a arista";
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
      boxes = [ "INBOX" "[Gmail]/Sent Mail" "Builds" "Escalation" "Work" "Reviews" "Packages" ];
      onNotify = "account=arista ${config.home.homeDirectory}/bin/update-mail";
      extraConfig = {
        tls = true;
        tlsOptions = {
          rejectUnauthorized = false;
        };
        xoauth2 = true;
      };
    };
  };

  # Aerc query map
  home.file.".config/aerc/work-map".source = ./config/aerc-work-map;

  # Notmuch config
  home.file.".config/notmuch/arista".source = ./config/notmuch-arista;
}
