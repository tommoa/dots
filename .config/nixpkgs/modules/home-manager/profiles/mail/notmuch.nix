{
  config,
  lib,
  ...
}: let
  # These settings are read by the shared Notmuch hooks. Keep mailbox policy
  # here; account identity and Maildir paths come from Home Manager accounts.
  notmuchAccounts = {
    personal = {
      aliases = [
        "tom@tommoa.me"
        "tommoa@ucc.asn.au"
      ];
      settings = {
        type = "gmail";
        trash = "[Gmail]/Bin";
      };
    };

    shared = {
      aliases = [];
      settings = {
        type = "gmail";
        folder_tags = ["rsvp"];
        rsvp = "RSVP";
      };
    };

    tommoa = {
      aliases = [];
      settings = {
        sent = "Sent Messages";
        trash = "Deleted Messages";
      };
    };

    work = {
      aliases = ["toma@aristanetworks.com"];
      settings = {
        folder_tags = [
          "escalation"
          "review"
          "review-archive"
          "package"
          "package-archive"
          "ci"
          "ci-archive"
          "indus-release"
          "quinn-release"
          "seine-release"
          "design-reviews"
        ];
        escalation = "Escalation";
        review = "Reviews";
        review-archive = "archived-reviews";
        package = "Packages";
        package-archive = "archived-packages";
        ci = "Builds";
        ci-archive = "archived-builds";
        indus-release = "indus-release";
        quinn-release = "quinn-release";
        seine-release = "seine-release";
        design-reviews = "Design Reviews";
        trash = "[Gmail]/Bin";
        type = "gmail";
        archive = "Work";
      };
    };
  };

  mkIniKeyValue = key: value: let
    formatValue = value:
      if lib.isString value
      then value
      else if lib.isList value
      then lib.concatMapStringsSep ";" formatValue value
      else if lib.isBool value
      then
        (
          if value
          then "true"
          else "false"
        )
      else toString value;
  in "${key}=${formatValue value}";

  toIni = lib.generators.toINI {mkKeyValue = mkIniKeyValue;};

  mkNotmuchConfig = accountName: metadata: let
    account = config.accounts.email.accounts.${accountName};
    isGmail = (metadata.settings.type or "") == "gmail";
    user =
      {
        name = account.realName;
        primary_email = account.address;
        inbox = account.folders.inbox;
        archive =
          if isGmail
          then "[Gmail]/All Mail"
          else "Archive";
        sent =
          if isGmail
          then "[Gmail]/Sent Mail"
          else "Sent";
        trash =
          if isGmail
          then "[Gmail]/Trash"
          else "Trash";
      }
      // lib.optionalAttrs (metadata.aliases != []) {
        other_email = metadata.aliases;
      }
      // metadata.settings;
  in
    toIni {
      database = {
        path = "${config.accounts.email.maildirBasePath}/${account.maildir.path}";
        hook_dir = ".config/notmuch/runtime-hooks";
      };

      inherit user;

      new = {
        tags = ["unread" "inbox"];
        ignore = [
          ".mbsyncstate"
          ".uidvalidity"
          ".mbsyncstate.lock"
          ".mbsyncstate.journal"
          ".mbsyncstate.new"
        ];
      };

      search.exclude_tags = ["deleted" "spam"];

      maildir.synchronize_flags = true;
    };
in {
  home.file =
    lib.mapAttrs' (
      accountName: metadata:
        lib.nameValuePair ".config/notmuch/${accountName}" {
          text = mkNotmuchConfig accountName metadata;
        }
    )
    notmuchAccounts;
}
