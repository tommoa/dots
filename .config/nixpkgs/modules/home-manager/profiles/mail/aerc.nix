{
  # Enable aerc with complete configuration
  programs.aerc = {
    enable = true;

    # Main aerc configuration
    extraConfig = {
      general = {
        # Required for nix-managed configs: Nix store files are always world-readable (0755),
        # but aerc requires accounts.conf to be 0600. This is safe because our accounts.conf
        # contains no credentials - all authentication uses passwordCommand pointing to
        # external tools (oauth2-gmail, msmtp) that handle credentials separately.
        unsafe-accounts-conf = true;
      };

      ui = {
        # Index display format
        index-columns = "date<20,name<17,flags>4,subject<*";
        column-separator = "  ";

        # Folder list format
        dirlist-format = "%n %>r";

        # Time/date formatting
        timestamp-format = "2006-01-02 03:04 PM";
        this-day-time-format = "03:04 PM";
        this-week-time-format = "Mon 03:04";
        this-year-time-format = "Jan 02";

        # UI settings
        sidebar-width = 22;
        empty-message = "(no messages)";
        empty-dirlist = "(no folders)";
        mouse-enabled = true;
        new-message-bell = true;
      };

      viewer = {
        pager = "less -R";
        alternatives = "text/plain,text/html";
        show-headers = false;
        header-layout = "From|To,Cc|Bcc,Date,Subject";
      };

      filters = {
        # HTML email rendering
        "text/html" = "w3m -dump -o display_link_number=1 -T text/html";

        # Plain text and other filters
        "text/plain" = "colorize";
        "text/calendar" = "calendar";
        "message/delivery-status" = "colorize";
        "message/rfc822" = "colorize";

        # Special filter for headers
        ".headers" = "colorize";
      };
    };

    # Keybindings configuration
    extraBinds = {
      # Global bindings
      global = {
        "<C-p>" = ":prev-tab<Enter>";
        "<C-PgUp>" = ":prev-tab<Enter>";
        "<C-n>" = ":next-tab<Enter>";
        "<C-PgDn>" = ":next-tab<Enter>";
        "\\[t" = ":prev-tab<Enter>";
        "\\]t" = ":next-tab<Enter>";
        "<C-t>" = ":term<Enter>";
        "<C-r>" = ":exec update-mail<Enter>";
        "?" = ":help keys<Enter>";
        "<C-c>" = ":prompt 'Quit?' quit<Enter>";
        "<C-q>" = ":prompt 'Quit?' quit<Enter>";
        "<C-z>" = ":suspend<Enter>";
      };

      # Message list bindings
      messages = {
        "q" = ":quit<Enter>";

        # Navigation
        "n" = ":next<Enter>";
        "<Down>" = ":next<Enter>";
        "<C-d>" = ":next 50%<Enter>";
        "<C-f>" = ":next 100%<Enter>";
        "<PgDn>" = ":next 100%<Enter>";

        "e" = ":prev<Enter>";
        "<Up>" = ":prev<Enter>";
        "<C-u>" = ":prev 50%<Enter>";
        "<C-b>" = ":prev 100%<Enter>";
        "<PgUp>" = ":prev 100%<Enter>";
        "g" = ":select 0<Enter>";
        "G" = ":select -1<Enter>";

        # Folder navigation
        "N" = ":next-folder<Enter>";
        "<C-Down>" = ":next-folder<Enter>";
        "E" = ":prev-folder<Enter>";
        "<C-Up>" = ":prev-folder<Enter>";
        "H" = ":collapse-folder<Enter>";
        "<C-Left>" = ":collapse-folder<Enter>";
        "I" = ":expand-folder<Enter>";
        "<C-Right>" = ":expand-folder<Enter>";

        # Marking
        "v" = ":mark -t<Enter>";
        "<Space>" = ":mark -t<Enter>:next<Enter>";
        "V" = ":mark -v<Enter>";

        # Threading
        "T" = ":toggle-threads<Enter>";
        "zc" = ":fold<Enter>";
        "zo" = ":unfold<Enter>";
        "za" = ":fold -t<Enter>";
        "zM" = ":fold -a<Enter>";
        "zR" = ":unfold -a<Enter>";
        "<tab>" = ":fold -t<Enter>";

        # Alignment
        "zz" = ":align center<Enter>";
        "zt" = ":align top<Enter>";
        "zb" = ":align bottom<Enter>";

        # Actions
        "<Enter>" = ":view<Enter>";

        # Tagging: single-key and dot-prefixed versions
        # Archive
        "a" = ":modify -inbox -deleted +archive<Enter>";
        ".a" = ":modify -inbox -deleted +archive<Enter>";
        # Delete
        "d" = ":modify -inbox -archive +deleted<Enter>";
        ".d" = ":modify -inbox -archive +deleted<Enter>";
        # Restore to inbox
        "u" = ":modify -deleted -archive +inbox<Enter>";
        ".u" = ":modify -deleted -archive +inbox<Enter>";
        # Toggle flags
        ".f" = ":flag -t -x Flagged<Enter>";
        ".s" = ":flag -t -x Seen<Enter>";
        # Manual label editing
        ".." = ":modify-labels<space>";

        # Thread variants
        "A" = ":mark -T<Enter>:modify -inbox -deleted +archive<Enter>";
        "D" = ":mark -T<Enter>:modify -inbox -archive +deleted<Enter>";
        "U" = ":mark -T<Enter>:modify -deleted -archive +inbox<Enter>";

        # Compose
        "C" = ":compose<Enter>";
        "m" = ":compose<Enter>";
        "b" = ":bounce<space>";
        "F" = ":forward<Enter>";

        # Reply
        "rr" = ":reply -a<Enter>";
        "rq" = ":reply -aq<Enter>";
        "Rr" = ":reply<Enter>";
        "Rq" = ":reply -q<Enter>";

        # Other commands
        "c" = ":cf<space>";
        "$" = ":term<space>";
        "!" = ":term<space>";
        "|" = ":pipe<space>";

        # Search
        "/" = ":search<space>";
        "\\" = ":filter<space>";
        "k" = ":next-result<Enter>";
        "K" = ":prev-result<Enter>";
        "<Esc>" = ":clear<Enter>";

        # Split view
        "s" = ":split<Enter>";
        "S" = ":vsplit<Enter>";

        # Patch management
        "pl" = ":patch list<Enter>";
        "pa" = ":patch apply <Tab>";
        "pd" = ":patch drop <Tab>";
        "pb" = ":patch rebase<Enter>";
        "pt" = ":patch term<Enter>";
        "ps" = ":patch switch <Tab>";
      };

      # Drafts folder bindings
      "messages:folder=Drafts" = {
        "<Enter>" = ":recall<Enter>";
      };

      # Message viewer bindings
      view = {
        "/" = ":toggle-key-passthrough<Enter>/";
        "q" = ":close<Enter>";
        "O" = ":open<Enter>";
        "o" = ":open<Enter>";
        "S" = ":save<space>";
        "|" = ":pipe<space>";

        # Tagging: single-key and dot-prefixed versions
        # Archive
        "a" = ":modify -inbox -deleted +archive<Enter>";
        ".a" = ":modify -inbox -deleted +archive<Enter>";
        # Delete
        "d" = ":modify -inbox -archive +deleted<Enter>";
        ".d" = ":modify -inbox -archive +deleted<Enter>";
        # Restore to inbox
        "u" = ":modify -deleted -archive +inbox<Enter>";
        ".u" = ":modify -deleted -archive +inbox<Enter>";
        # Toggle flags
        ".f" = ":flag -t -x Flagged<Enter>";
        ".s" = ":flag -t -x Seen<Enter>";
        # Manual label editing
        ".." = ":modify-labels<space>";

        "<C-y>" = ":copy-link <space>";
        "<C-l>" = ":open-link <space>";

        "F" = ":forward<Enter>";
        "rr" = ":reply -a<Enter>";
        "rq" = ":reply -aq<Enter>";
        "Rr" = ":reply<Enter>";
        "Rq" = ":reply -q<Enter>";

        "H" = ":toggle-headers<Enter>";
        "<C-e>" = ":prev-part<Enter>";
        "<C-Up>" = ":prev-part<Enter>";
        "<C-n>" = ":next-part<Enter>";
        "<C-Down>" = ":next-part<Enter>";
        "N" = ":next<Enter>";
        "<C-Right>" = ":next<Enter>";
        "E" = ":prev<Enter>";
        "<C-Left>" = ":prev<Enter>";
      };

      # Passthrough mode bindings
      "view::passthrough" = {
        "$noinherit" = "true";
        "$ex" = "<C-x>";
        "<Esc>" = ":toggle-key-passthrough<Enter>";
      };

      # Compose view bindings
      compose = {
        "$noinherit" = "true";
        "$ex" = "<C-x>";
        "$complete" = "<C-o>";
        "<C-k>" = ":prev-field<Enter>";
        "<C-Up>" = ":prev-field<Enter>";
        "<C-j>" = ":next-field<Enter>";
        "<C-Down>" = ":next-field<Enter>";
        "<A-p>" = ":switch-account -p<Enter>";
        "<C-Left>" = ":switch-account -p<Enter>";
        "<A-n>" = ":switch-account -n<Enter>";
        "<C-Right>" = ":switch-account -n<Enter>";
        "<tab>" = ":next-field<Enter>";
        "<backtab>" = ":prev-field<Enter>";
        "<C-p>" = ":prev-tab<Enter>";
        "<C-PgUp>" = ":prev-tab<Enter>";
        "<C-n>" = ":next-tab<Enter>";
        "<C-PgDn>" = ":next-tab<Enter>";
      };

      # Compose editor bindings
      "compose::editor" = {
        "$noinherit" = "true";
        "$ex" = "<C-x>";
        "<C-k>" = ":prev-field<Enter>";
        "<C-Up>" = ":prev-field<Enter>";
        "<C-j>" = ":next-field<Enter>";
        "<C-Down>" = ":next-field<Enter>";
        "<C-p>" = ":prev-tab<Enter>";
        "<C-PgUp>" = ":prev-tab<Enter>";
        "<C-n>" = ":next-tab<Enter>";
        "<C-PgDn>" = ":next-tab<Enter>";
      };

      # Compose review bindings
      "compose::review" = {
        "y" = ":send<Enter>";
        "n" = ":abort<Enter>";
        "s" = ":sign<Enter>";
        "x" = ":encrypt<Enter>";
        "v" = ":preview<Enter>";
        "p" = ":postpone<Enter>";
        "q" = ":choose -o d discard abort -o p postpone postpone<Enter>";
        "e" = ":edit<Enter>";
        "a" = ":attach<space>";
        "d" = ":detach<space>";
      };

      # Terminal bindings
      terminal = {
        "$noinherit" = "true";
        "$ex" = "<C-x>";
        "<C-p>" = ":prev-tab<Enter>";
        "<C-n>" = ":next-tab<Enter>";
        "<C-PgUp>" = ":prev-tab<Enter>";
        "<C-PgDn>" = ":next-tab<Enter>";
      };

      # Work account-specific bindings (messages)
      "messages:account=work" = {
        ".r" = ":modify -review +review-archive<Enter>";
        ".R" = ":modify +review -review-archive<Enter>";
        ".p" = ":modify -package +package-archive<Enter>";
        ".P" = ":modify +package -package-archive<Enter>";
        ".c" = ":modify -ci +ci-archive<Enter>";
        ".C" = ":modify +ci -ci-archive<Enter>";
      };

      # Work account-specific bindings (view)
      "view:account=work" = {
        ".r" = ":modify -review +review-archive<Enter>";
        ".R" = ":modify +review -review-archive<Enter>";
        ".p" = ":modify -package +package-archive<Enter>";
        ".P" = ":modify +package -package-archive<Enter>";
        ".c" = ":modify -ci +ci-archive<Enter>";
        ".C" = ":modify +ci -ci-archive<Enter>";
      };
    };
  };
}
