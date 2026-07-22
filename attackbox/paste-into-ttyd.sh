# NOT a script to run locally. This is the block to COPY (on your own machine,
# from wherever you're reading this) and PASTE into the ttyd browser terminal
# *after* you've typed the AttackBox root password and landed on its shell.
# Inbound paste into ttyd is unaffected by the OSC-52 clipboard gap (that gap
# only blocks copying OUT of the browser terminal) -- normal paste (Ctrl+Shift+V,
# or your browser/terminal's paste binding) works fine for this.
#
# It writes ~/.tmux.conf on the AttackBox and drops you straight into tmux.
# There's no scp path to the AttackBox from the broker side (session.sh execs
# ssh directly, no shell hop), so this heredoc is the transfer mechanism.

cat > ~/.tmux.conf << 'ATTACKBOX_TMUX_CONF_EOF'
set -g mouse on
set -g history-limit 50000
set -g escape-time 10
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g mode-keys vi
setw -g aggressive-resize on
set -g status-style bg=colour234,fg=colour250
set -g status-left ''
set -g status-right '#[fg=colour244]%H:%M '
setw -g window-status-current-style bg=colour238,fg=colour255,bold
ATTACKBOX_TMUX_CONF_EOF
tmux new -s main
