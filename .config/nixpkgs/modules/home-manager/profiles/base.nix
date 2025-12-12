{ config, pkgs, ... }:

{
  # Agenix base configuration - just set the identity path
  # Secrets are defined in secrets/*.nix profiles
  age.identityPaths = [
    "${config.home.homeDirectory}/.ssh/id_ed25519"
  ];

  home.packages = with pkgs; [
    # Standard terminal tools
    bat
    eza
    fd
    git
    gnupg
    gnumake
    jq
    ripgrep
    tmux

    # Terminal editing
    neovim
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autocd = true;
    defaultKeymap = "viins";

    # Speed up compinit by invalidating cache only when fpath changes
    completionInit = ''
      autoload -Uz compinit
      _comp_path="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
      _comp_check="''${_comp_path}.fpath"
      _current_hash=''${(j::)fpath:A}
      mkdir -p "''${_comp_path:h}"
      if [[ -f "$_comp_path" && -f "$_comp_check" && "$(<$_comp_check)" == "$_current_hash" ]]; then
        compinit -C -d "$_comp_path"
      else
        compinit -d "$_comp_path"
        echo "$_current_hash" > "$_comp_check"
      fi
      unset _comp_path _comp_check _current_hash
    '';

    history = {
      path = "${config.home.homeDirectory}/.zsh_history";
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
      extended = true;
    };

    setOptions = [
      "HIST_NO_STORE"
      "INTERACTIVE_COMMENTS"
      "LONG_LIST_JOBS"
      "PRINT_EXIT_VALUE"
      "RC_QUOTES"
      "PROMPT_SUBST"
    ];

    localVariables = {
      GIT_PROMPT = "1";
    };

    initContent = ''
      # Source .env for environment-specific settings
      [ -f ~/.env ] && source ~/.env

      # Custom prompt with git integration
      prompt_git() {
          [[ "''${GIT_PROMPT}" == "1" ]] || return
          git rev-parse --is-inside-work-tree &>/dev/null || return

          local branch
          branch=$(git symbolic-ref --short -q HEAD 2>/dev/null) || \
              branch=$(git rev-parse --short HEAD 2>/dev/null)

          local num_added=0 num_removed=0 total=0
          while IFS=$'\t' read -r added removed _; do
              (( num_added += added, num_removed += removed, total++ ))
          done < <(git diff-files --numstat 2>/dev/null)

          local totals=""
          if (( total > 0 )); then
              totals=":%F{blue}''${total}"
              (( num_added > 0 )) && totals+="%F{85}+''${num_added}"
              (( num_removed > 0 )) && totals+="%F{red}-''${num_removed}"
          fi

          print -n "%B[%F{red}''${branch}%f''${totals}%f] %b"
      }
      PROMPT=%F{85}%B%n''${SSH_CLIENT:+%F{red}@%F{cyan}%U%m%u}%f:%F{75}%~%f\#%b\ \$(prompt_git)
      RPROMPT=%T

      # Tab completion
      bindkey '^[=' expand-cmd-path

      # Arrow keys for history search
      autoload -U history-search-end
      zle -N history-beginning-search-backward-end history-search-end
      zle -N history-beginning-search-forward-end history-search-end
      bindkey "^[[A" history-beginning-search-backward-end
      bindkey "^[[B" history-beginning-search-forward-end
      bindkey "''${terminfo[kcuu1]}" history-beginning-search-backward-end
      bindkey "''${terminfo[kcud1]}" history-beginning-search-forward-end

      # Additional keybindings
      bindkey '^U' kill-whole-line
      bindkey '^R' history-incremental-search-backward

      # Colemak-style vi-mode remappings
      bindkey -a "n" vi-down-line-or-history
      bindkey -a "N" vi-join
      bindkey -a "e" vi-up-line-or-history
      bindkey -a "i" vi-forward-char
      bindkey -a "u" vi-insert
      bindkey -a "U" vi-insert-bol
      bindkey -a "k" vi-repeat-search
      bindkey -a "K" vi-rev-repeat-search
      bindkey -a "l" vi-undo
      bindkey -a "j" vi-forward-word-end
      bindkey -a "J" vi-forward-blank-word-end

      bindkey '\e[1~' beginning-of-line
      bindkey '\e[4~' end-of-line

      # Disable core dumps
      limit coredumpsize 0

      # Completion styling
      zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
      zstyle ':completion:*' menu select=long
      ZLS_COLOURS="''${(s.:.)LS_COLORS}"

      stty -ixon
    '';
  };

  programs.nix-your-shell = {
    enable = true;
    enableZshIntegration = true;
  };

  home.stateVersion = "25.05";
  programs.home-manager.enable = true;
}
