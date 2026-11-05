{
  pkgs,
  config,
  lib,
  ...
}: let
  mailRuntime = pkgs.callPackage ./mail/runtime.nix {
    mbsync = config.programs.mbsync.package;
    gnupg = config.programs.gpg.package;
  };
  tmuxStatus = pkgs.writeShellApplication {
    name = "mail-sync-tmux-status";
    text = lib.replaceStrings ["@updateMail@"] [
      (lib.escapeShellArg "${mailRuntime}/bin/update-mail")
    ] (builtins.readFile ./mail/tmux-status.sh);
  };
  notifyAccounts = lib.filterAttrs (_: account: account.enable && account.imapnotify.enable) config.accounts.email.accounts;
  logDir = "${config.home.homeDirectory}/.local/state/imapnotify";
  # Match Home Manager's imapnotify service names when extending its agents.
  safeName = lib.replaceStrings ["@" ":" "\\" "[" "]"] ["-" "-" "-" "" ""];
in {
  # Import account and program configurations
  imports = [
    ./mail/aerc.nix
    ./mail/notmuch.nix
    ./mail/accounts/personal.nix
    ./mail/accounts/work.nix
    ./mail/accounts/tommoa.nix
    ./mail/accounts/shared.nix
    ./secrets/mail-encryption.nix
  ];

  # Account modules use these commands as argv lists, so runtime secret paths
  # never pass through Home Manager's string-to-argv splitting.
  _module.args.mailRuntime = mailRuntime;

  home.packages = with pkgs; [
    mailRuntime
    notmuch # Email indexing and tagging
    w3m-images # HTML email viewing in aerc
  ];

  # Configure base maildir path
  accounts.email.maildirBasePath = ".mail";

  # Enable mbsync with home-manager
  programs.mbsync = {
    enable = true;
    package = pkgs.isync.override {
      withCyrusSaslXoauth2 = true;
    };
  };

  # Git send-email uses the SMTP transport from this mail profile.
  programs.git.settings.sendemail = {
    smtpServer = lib.getExe config.programs.msmtp.package;
    annotate = true;
  };

  # Enable msmtp with home-manager
  programs.msmtp = {
    enable = true;
  };

  programs.gpg.enable = true;

  # Enable imapnotify service for automatic mail sync
  services.imapnotify.enable = true;

  home.file.".config/notmuch/runtime-hooks".source = "${mailRuntime}/libexec/notmuch-hooks";

  # Use the same updater from the shell as from aerc and imapnotify.
  # force replaces the old symlink into this checkout.
  home.file."bin/update-mail" = {
    source = "${mailRuntime}/bin/update-mail";
    force = true;
  };

  home.file.".tmux-mail.conf".text = ''
    set -g @mail_sync_segment "#(${tmuxStatus}/bin/mail-sync-tmux-status)"
  '';

  # launchd does not inherit shell startup configuration. The packaged commands
  # carry their dependencies; capture startup failures in private, readable logs.
  launchd.agents = lib.mkIf pkgs.stdenv.isDarwin (lib.mapAttrs' (name: _: let
    serviceName = "imapnotify-${safeName name}";
  in
    lib.nameValuePair serviceName {
      config = {
        StandardOutPath = "${logDir}/${safeName name}.stdout.log";
        StandardErrorPath = "${logDir}/${safeName name}.stderr.log";
      };
    })
  notifyAccounts);

  systemd.user.services = lib.mkIf pkgs.stdenv.isLinux (lib.mapAttrs' (name: _:
    lib.nameValuePair "imapnotify-${safeName name}" {
      Unit = {
        After = ["agenix.service"];
        Requires = ["agenix.service"];
      };
    })
  notifyAccounts);

  home.activation.mailLogDirectory = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryBetween ["setupLaunchAgents"] ["linkGeneration" "importMailEncryptionKey"] ''
      run ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg logDir}
    ''
  );

  # w3m configuration for HTML email rendering
  home.file.".w3m/config".text = ''
    inline_img_protocol 4
    display_borders 0
  '';

  home.file.".w3m/keymap".text = ''
    # w3m keymap — Colemak layout matching neovim keybinds
    #
    # Core navigation (Colemak):
    #   h = left, n = down, e = up, i = right
    #   k = next search, K = prev search
    #   j = next word, J = prev word

    # First unbind keys we're reassigning
    keymap n NULL
    keymap e NULL
    keymap i NULL
    keymap j NULL
    keymap k NULL
    keymap K NULL
    keymap J NULL
    keymap l NULL
    keymap L NULL
    keymap u NULL
    keymap U NULL
    keymap N NULL
    keymap E NULL
    keymap I NULL

    # Colemak cursor movement
    keymap n MOVE_DOWN
    keymap e MOVE_UP
    keymap i MOVE_RIGHT
    keymap h MOVE_LEFT

    # Word movement
    keymap j NEXT_WORD
    keymap J PREV_WORD

    # Search (k/K in Colemak = n/N in standard vim)
    keymap k SEARCH_NEXT
    keymap K SEARCH_PREV
    keymap / ISEARCH
    keymap ? ISEARCH_BACK

    # Page/scroll navigation
    keymap C-f NEXT_PAGE
    keymap C-b PREV_PAGE
    keymap C-d NEXT_PAGE
    keymap C-u PREV_PAGE

    # Top/bottom
    keymap g BEGIN
    keymap G END

    # Line begin/end
    keymap 0 LINE_BEGIN
    keymap $ LINE_END

    # Links
    keymap TAB NEXT_LINK
    keymap ESC-TAB PREV_LINK
    keymap RET GOTO_LINK

    # History navigation
    keymap H PREV
    keymap L NEXT

    # Misc
    keymap r RELOAD
    keymap q QUIT
    keymap Q EXIT
    keymap ZZ EXIT
  '';

  # Ensure mail directories exist
  home.file.".mail/.keep".text = "";
}
