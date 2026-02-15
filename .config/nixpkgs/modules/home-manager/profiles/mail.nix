{
  pkgs,
  config,
  lib,
  ...
}: {
  # Import account and program configurations
  imports = [
    ./mail/aerc.nix
    ./mail/accounts/personal.nix
    ./mail/accounts/work.nix
    ./mail/accounts/tommoa.nix
    ./mail/accounts/shared.nix
  ];

  home.packages = with pkgs; [
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

  # Enable msmtp with home-manager
  programs.msmtp = {
    enable = true;
  };

  # Enable imapnotify service for automatic mail sync
  services.imapnotify.enable = true;

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
