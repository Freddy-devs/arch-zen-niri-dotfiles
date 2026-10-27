# ~/.zshrc — arch-zen-niri

typeset -U path
path=("$HOME/.local/bin" "$HOME/.config/composer/vendor/bin" $path)
export EDITOR=nano VISUAL=nano

HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt hist_ignore_all_dups share_history inc_append_history autocd

autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
bindkey -e

source <(fzf --zsh)
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

alias ls='eza --icons --group-directories-first'
alias ll='eza -l --icons --git --group-directories-first'
alias la='eza -la --icons --git --group-directories-first'
alias cat='bat --paging=never'
alias docker='podman'
alias update='sudo pacman -Syu'
alias news='arch-news 30'

eval "$(starship init zsh)"
