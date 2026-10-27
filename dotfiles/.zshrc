# ~/.zshrc — arch-zen-niri

[[ $- != *i* ]] && return

typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/.config/composer/vendor/bin" $path)
export EDITOR=nano VISUAL=nano
export TERMINAL=alacritty
export BAT_THEME="base16"
export SUDO_PROMPT="Acceso root para %u. Contraseña: "

# ---------- historial: recuerda todo lo que escribes, compartido entre terminales
HISTFILE=~/.config/zsh/zhistory
HISTSIZE=100000
SAVEHIST=100000
[[ -d ${HISTFILE:h} ]] || mkdir -p ${HISTFILE:h}
setopt extended_history       # guarda fecha y duración
setopt inc_append_history     # escribe al momento, no al cerrar
setopt share_history          # lo de una terminal aparece en las demás
setopt hist_ignore_all_dups hist_save_no_dups hist_find_no_dups
setopt hist_ignore_space      # " comando" (con espacio delante) no se guarda
setopt hist_reduce_blanks hist_verify

# ---------- completado: comandos, opciones y paquetes de todo lo instalado
# zsh-completions suma ~1000 programas (podman, composer, systemctl, git, gh, npm...)
fpath=(/usr/share/zsh/site-functions $fpath)
autoload -Uz compinit
# el índice se regenera una vez al día; el resto de veces carga rápido (-C)
_dump=(~/.config/zsh/zcompdump(N.mh-24))
if (( $#_dump )); then
    compinit -C -d ~/.config/zsh/zcompdump
else
    compinit -d ~/.config/zsh/zcompdump
fi
unset _dump
_comp_options+=(globdots)

zstyle ':completion:*' menu select
zstyle ':completion:*' rehash true            # ve los programas recién instalados
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.cache/zsh/compcache
zstyle ':completion:*' group-name ''
zstyle ':completion:*' squeeze-slashes true
# sin distinguir mayúsculas y completando por partes: "s.d" → systemctl daemon-reload, "nv" → nvim
zstyle ':completion:*' matcher-list '' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%F{#7aa2f7}── %d ──%f'
zstyle ':completion:*:messages' format '%F{#565f89}%d%f'
zstyle ':completion:*:warnings' format '%F{#f7768e}nada para: %d%f'
zstyle ':completion:*:processes' command 'ps -u $USER -o pid,%cpu,%mem,comm'

setopt autocd menu_complete list_packed auto_list complete_in_word interactive_comments
bindkey -e

# ---------- prompt:  usuario  carpeta  git-[ rama]- ❯
# Se arma en cada precmd (sin prompt_subst: un nombre de rama no puede ejecutar nada).
autoload -Uz add-zsh-hook vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' %B%F{#a9b1d6}git-[%F{#bb9af7}%F{#e0af68} %b%F{#a9b1d6}]-%f%%b'
zstyle ':vcs_info:git:*' actionformats ' %B%F{#a9b1d6}git-[%F{#bb9af7}%F{#e0af68} %b %F{#f7768e}%a%F{#a9b1d6}]-%f%%b'

_zen_prompt() {
    vcs_info
    local here=''
    [[ $PWD == "$HOME" ]] && here=''
    PROMPT="%B%F{#7aa2f7}%f  %F{#bb9af7}%n%f  %F{#7dcfff}${here}%f  %F{#f7768e}%~%f%b${vcs_info_msg_0_} %B%(?.%F{#9ece6a}.%F{#f7768e})%f%b "
}
add-zsh-hook precmd _zen_prompt

# ---------- plugins
# sugerencia en gris mientras escribes: primero tu historial, si no hay, el completado (→ acepta)
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#565f89'
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# ↑/↓ buscan en el historial lo que ya escribiste ("git c" + ↑ = último "git c...")
source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '^[OA' history-substring-search-up
bindkey '^[OB' history-substring-search-down
bindkey '^[[3~' delete-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# Ctrl+R historial con búsqueda difusa · Ctrl+T archivos · Alt+C carpetas
source <(fzf --zsh)
export FZF_DEFAULT_OPTS="--height 40% --layout reverse --border rounded \
  --color=bg+:#292e42,fg+:#c0caf5,hl:#bb9af7,hl+:#bb9af7,pointer:#f7768e,prompt:#7aa2f7,info:#565f89,border:#292e42"
# z <fragmento> salta a carpetas que ya visitaste · zi = elegir con fzf
eval "$(zoxide init zsh)"

# comando que no existe: dice qué paquete lo trae (pkgfile)
if [[ -r /usr/share/doc/pkgfile/command-not-found.zsh ]]; then
    source /usr/share/doc/pkgfile/command-not-found.zsh
fi

# ---------- título de la ventana: la carpeta, o el comando mientras corre
_zen_title_idle() { print -Pn -- '\e]0;%~\a' }
_zen_title_run()  { print -rn -- $'\e]0;'"${${1[1,80]}//[^[:print:]]/}"$'\a' }
add-zsh-hook precmd _zen_title_idle
add-zsh-hook preexec _zen_title_run

# ---------- alias
alias ls='eza --icons=always --color=always -a --group-directories-first'
alias ll='eza --icons=always --color=always -la --git --group-directories-first'
alias cat='bat --paging=never'
alias docker='podman'
alias update='sudo pacman -Syu'
alias news='arch-news 30'
alias grub-update='sudo grub-mkconfig -o /boot/grub/grub.cfg'
alias neofetch='fastfetch'
alias htop='btop'

# ---------- banner pixel-art al abrir una terminal nueva (no en nvim, tmux, Claude Code ni subshells)
if [[ $(ps -o comm= -p $PPID 2>/dev/null) == alacritty && -z $TMUX$NVIM$CLAUDE_CODE_SESSION_ID ]]; then
    zen-banner 2>/dev/null
fi
# si un programa termina dejando el cursor oculto, vuelve a mostrarlo
add-zsh-hook precmd _zen_cursor
_zen_cursor() { print -n '\e[?25h' }
