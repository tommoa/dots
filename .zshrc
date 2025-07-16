# Only zsh specific things will be in this file

# Source .env
source ~/.env

autoload -U colors && colors

prompt_git() {
    # Because ANSI colour codes are borked on ZSH, if we use PS1 it shifts the
    # RPROMPT, so we need a custom function
    # To see a fully POSIX version of this function, see ~/.env

    if [ "${GIT_PROMPT}" = "1" ] && git rev-parse --is-inside-work-tree -q >/dev/null 2>&1; then
        eval $(git diff-files --numstat -r 2>/dev/null | awk '{add+=$1; remove+=$2} END {printf "num_added='%d';num_removed='%d';total='%d';", add, remove, NR}')
        totals="";
        if [ "${total}" -gt 0 ]; then
            totals=":%%F{blue}${total}"
            [ "${num_added}" -gt 0 ] && totals="${totals}%%F{85}+${num_added}"
            [ "${num_removed}" -gt 0 ] && totals="${totals}%%F{red}-${num_removed}"
        fi
        printf "%%B[%%F{red}$(git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)%%f${totals}%%f] %%b"
    fi
}
setopt prompt_subst
PROMPT=%F{85}%B%n${SSH_CLIENT:+%F{red}@%F{cyan}%U%m%u}%f:%F{75}%~%f\#%b\ \$(prompt_git)
RPROMPT=%T

# zsh options - see zshoptions(1)
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_NO_STORE INTERACTIVE_COMMENTS
setopt LONG_LIST_JOBS PRINT_EXIT_VALUE RC_QUOTES
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

# key bindings
bindkey -v
# tab completion
bindkey '^[=' expand-cmd-path
# arrow keys
autoload -U history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey "^[[A" history-beginning-search-backward-end
bindkey "^[[B" history-beginning-search-forward-end
bindkey "${terminfo[kcuu1]}" history-beginning-search-backward-end
bindkey "${terminfo[kcud1]}" history-beginning-search-forward-end
# ^U kills the entire line, not just back from cursor
bindkey '^U' kill-whole-line
bindkey '^R' history-incremental-search-backward
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

zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu select=long

ZLS_COLOURS="${(s.:.)LS_COLORS}"
autoload -U compinit && compinit
autoload -U bashcompinit && bashcompinit

setopt auto_cd
stty -ixon
export GIT_PROMPT=1

if which nix-your-shell >/dev/null 2>/dev/null; then
    nix-your-shell zsh | source /dev/stdin
fi
