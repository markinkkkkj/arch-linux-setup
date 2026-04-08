# ── Histórico ────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

# ── Opções gerais ─────────────────────────────────────────────
setopt AUTO_CD
setopt CORRECT
setopt GLOB_COMPLETE

# ── Completion ────────────────────────────────────────────────
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# ── Prompt (simples, sem framework) ──────────────────────────
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'
setopt PROMPT_SUBST
PROMPT='%F{cyan}%~%f%F{yellow}${vcs_info_msg_0_}%f %# '

# ── Plugins (instalados via pacman) ──────────────────────────
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh 2>/dev/null
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null

# ── Keybindings ──────────────────────────────────────────────
bindkey -e                          # modo emacs (Ctrl+A, Ctrl+E, etc.)
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
bindkey '^[[1;5C' forward-word      # Ctrl+Direita — pular palavra
bindkey '^[[1;5D' backward-word     # Ctrl+Esquerda — voltar palavra

# ── Seleção com Shift+Setas ───────────────────────────────────
zle_highlight=(region:standout)

select-forward-char()  { (( REGION_ACTIVE )) || zle set-mark-command; zle forward-char  }
select-backward-char() { (( REGION_ACTIVE )) || zle set-mark-command; zle backward-char }
select-forward-word()  { (( REGION_ACTIVE )) || zle set-mark-command; zle forward-word  }
select-backward-word() { (( REGION_ACTIVE )) || zle set-mark-command; zle backward-word }
zle -N select-forward-char
zle -N select-backward-char
zle -N select-forward-word
zle -N select-backward-word

bindkey '^[[1;2C' select-forward-char   # Shift+Direita
bindkey '^[[1;2D' select-backward-char  # Shift+Esquerda
bindkey '^[[1;6C' select-forward-word   # Ctrl+Shift+Direita
bindkey '^[[1;6D' select-backward-word  # Ctrl+Shift+Esquerda

deselect-forward-char()  { REGION_ACTIVE=0; zle forward-char  }
deselect-backward-char() { REGION_ACTIVE=0; zle backward-char }
deselect-forward-word()  { REGION_ACTIVE=0; zle forward-word  }
deselect-backward-word() { REGION_ACTIVE=0; zle backward-word }
zle -N deselect-forward-char
zle -N deselect-backward-char
zle -N deselect-forward-word
zle -N deselect-backward-word

# Integração com zsh-autosuggestions: wrappear nossos widgets também
ZSH_AUTOSUGGEST_ACCEPT_WIDGETS+=(deselect-forward-char)
ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS+=(deselect-forward-word)

bindkey '^[[C'     deselect-forward-char   # Direita
bindkey '^[[D'     deselect-backward-char  # Esquerda
bindkey '^[[1;5C'  deselect-forward-word   # Ctrl+Direita
bindkey '^[[1;5D'  deselect-backward-word  # Ctrl+Esquerda

# ── PATH ─────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=nvim

# ── Aliases ──────────────────────────────────────────────────
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# ── nvm ──────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
