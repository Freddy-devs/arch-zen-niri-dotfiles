# ~/.zshrc — arch-zen-niri

[[ $- != *i* ]] && return

typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/.config/composer/vendor/bin" $path)
export EDITOR=nano VISUAL=nano
export TERMINAL=alacritty
export BAT_THEME="base16"
export SUDO_PROMPT="Acceso root para %u. Contraseña: "
# Erlang/Elixir (mix, iex): sin espera activa, los hilos de la VM no queman CPU mientras esperan
export ERL_AFLAGS="+sbwt none +sbwtdcpu none +sbwtdio none"

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
zstyle ':completion:*:descriptions' format '%F{#88c0d0}── %d ──%f'
zstyle ':completion:*:messages' format '%F{#616e88}%d%f'
zstyle ':completion:*:warnings' format '%F{#bf616a}nada para: %d%f'
zstyle ':completion:*:processes' command 'ps -u $USER -o pid,%cpu,%mem,comm'

setopt autocd menu_complete list_packed auto_list complete_in_word interactive_comments
bindkey -e

# ---------- prompt: [arch] usuario [carpeta] …/padre/hijo git-[rama] ❯
# Se arma en cada precmd (sin prompt_subst: un nombre de rama no puede ejecutar nada).
autoload -Uz add-zsh-hook vcs_info
zstyle ':vcs_info:*' enable git
# los iconos van como escapes \u (Nerd Font): así no se pierden al copiar o editar el archivo
_zi_branch=$'\ue0a0'
zstyle ':vcs_info:git:*' formats " %B%F{#d8dee9}git-[%F{#ebcb8b}${_zi_branch} %b%F{#d8dee9}]%f%%b"
zstyle ':vcs_info:git:*' actionformats " %B%F{#d8dee9}git-[%F{#ebcb8b}${_zi_branch} %b %F{#bf616a}%a%F{#d8dee9}]%f%%b"
unset _zi_branch

_zen_prompt() {
    vcs_info
    local arch=$'\uf303' home=$'\uf015' dir=$'\uf07c' arrow=$'\u276f'
    local here=$dir
    [[ $PWD == "$HOME" ]] && here=$home
    # ruta corta: solo padre/hijo cuando es más profunda  →  …/proyectos/mi-app
    # flecha verde (rojo si el último comando falló) marca dónde empieza lo que escribes
    PROMPT="%B%F{#88c0d0}${arch}%f %F{#c9a6ff}%n%f %F{#8fbcbb}${here}%f %F{#ff8a92}%(4~|…/%2~|%~)%f%b${vcs_info_msg_0_} %B%(?.%F{#a3be8c}.%F{#bf616a})${arrow}%f%b "
}
add-zsh-hook precmd _zen_prompt


# ---------- plugins
# sugerencia en gris mientras escribes: primero tu historial, si no hay, el completado (→ acepta)
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#616e88'
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
  --color=bg+:#3b4252,fg+:#eceff4,hl:#b48ead,hl+:#b48ead,pointer:#bf616a,prompt:#88c0d0,info:#616e88,border:#3b4252"
# z <fragmento> salta a carpetas que ya visitaste · zi = elegir con fzf
eval "$(zoxide init zsh)"

# comando que no existe: dice qué paquete lo trae (pkgfile)
if [[ -r /usr/share/doc/pkgfile/command-not-found.zsh ]]; then
    source /usr/share/doc/pkgfile/command-not-found.zsh
    # el aviso también con sangría, bajo la f de freddy
    functions -c command_not_found_handler _zen_cnf_pkgfile
    command_not_found_handler() { _zen_cnf_pkgfile "$@" 2>&1 | _zen_ind >&2; return 127 }
fi

# ---------- título de la ventana: la carpeta, o el comando mientras corre
_zen_title_idle() { print -Pn -- '\e]0;%~\a' }
_zen_title_run()  { print -rn -- $'\e]0;'"${${1[1,80]}//[^[:print:]]/}"$'\a' }
add-zsh-hook precmd _zen_title_idle
add-zsh-hook preexec _zen_title_run

# ---------- alias
# ls en columnas alineadas y ordenadas por nombre (carpetas primero); ll = lista detallada
export EZA_ICON_SPACING=1
# lo que imprimen ls, ll y cat empieza bajo la f de freddy (2 columnas, como un párrafo con sangría);
# solo en pantalla: en tuberías y archivos (ls | grep, cat x > y) sale tal cual
_zen_ind() { sed -u 's/^/  /' }
ls() {
    local opts=(--icons=always --color=always -a --group-directories-first --sort=name --grid --across)
    (( $# )) || set -- .   # sin carpeta: la actual (eza 0.23 si no, lee la lista desde stdin)
    if [[ -t 1 ]]; then eza $opts --width=$((COLUMNS - 2)) "$@" | _zen_ind; else eza $opts "$@"; fi
}
ll() {
    local opts=(--icons=always --color=always -la --git --group-directories-first)
    (( $# )) || set -- .
    if [[ -t 1 ]]; then eza $opts "$@" | _zen_ind; else eza $opts "$@"; fi
}
cat() {
    if [[ -t 1 ]]; then bat --paging=never --color=always --terminal-width=$((COLUMNS - 2)) "$@" | _zen_ind
    else bat --paging=never "$@"; fi
}
alias docker='podman'
alias update='sudo pacman -Syu'
alias news='arch-news 30'
alias grub-update='sudo grub-mkconfig -o /boot/grub/grub.cfg'
alias neofetch='fastfetch'
alias htop='btop'

# ---------- Node.js con fnm (zen-apps node): cambia de versión sola al entrar a un proyecto con .nvmrc
command -v fnm >/dev/null && eval "$(fnm env --use-on-cd --version-file-strategy=recursive --shell zsh)"

# ---------- banner pixel-art al abrir una terminal nueva (no en nvim, tmux, Claude Code ni subshells)
if [[ $(ps -o comm= -p $PPID 2>/dev/null) == alacritty && -z $TMUX$NVIM$CLAUDE_CODE_SESSION_ID ]]; then
    zen-banner 2>/dev/null
fi
# si un programa termina dejando el cursor oculto, vuelve a mostrarlo
add-zsh-hook precmd _zen_cursor
_zen_cursor() { print -n '\e[?25h' }
