# ── Histórico ────────────────────────────────────────────────
HISTFILE=~/.bash_history
HISTSIZE=10000
HISTFILESIZE=10000
HISTCONTROL=ignoreboth
shopt -s histappend

# ── Opções gerais ─────────────────────────────────────────────
shopt -s autocd
shopt -s checkwinsize

# ── Completion ────────────────────────────────────────────────
[ -r /usr/share/bash-completion/bash_completion ] && \
    source /usr/share/bash-completion/bash_completion

# ── Prompt ──────────────────────────────────────────────────
_git_branch() {
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null) && echo " ($branch)"
}
PS1='\[\e[36m\]\w\[\e[0m\]\[\e[33m\]$(_git_branch)\[\e[0m\] \$ '

# ── Keybindings ──────────────────────────────────────────────
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind '"\e[1;5C": forward-word'       # Ctrl+Direita — pular palavra
bind '"\e[1;5D": backward-word'      # Ctrl+Esquerda — voltar palavra

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
