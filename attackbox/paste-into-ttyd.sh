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
#
# Alternative, if the AttackBox has outbound internet access: skip this file
# entirely and just run, after logging in --
#   curl -fsSL https://raw.githubusercontent.com/lhGWTS/ttyd-vpn-ssh-broker/main/attackbox/tmux.conf -o ~/.tmux.conf && tmux new -s main
# One line, always pulls whatever's currently in the repo, and needs no local
# copy of this file kept in sync. Use the heredoc below only if the AttackBox
# has no internet egress.

cat > ~/.tmux.conf << 'ATTACKBOX_TMUX_CONF_EOF'
set -g mouse on
set -g history-limit 50000
set -g escape-time 10
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
setw -g aggressive-resize on
setw -g mode-keys vi
set -g default-terminal "tmux-256color"
set -sa terminal-overrides ',xterm-256color:RGB'
set-option -g set-clipboard on
set -g prefix C-t
unbind C-b
set-option -g status-position top
set-option -g status-left-length 90
set-option -g status-right-length 90
set-option -g status-left '#H:[#P]'
set-option -g status-right '[%Y-%m-%d(%a) %H:%M]'
set-option -g status-interval 1
set-option -g status-justify centre
set-option -g status-bg "colour238"
set-option -g status-fg "colour255"
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5
bind | split-window -h
bind - split-window -v
bind-key -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'select-pane -t=; copy-mode -e; send-keys -M'"
bind-key -n WheelDownPane select-pane -t= \; send-keys -M
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi V send -X select-line
bind -T copy-mode-vi C-v send -X rectangle-toggle
bind -T copy-mode-vi y send -X copy-selection-and-cancel
bind -T copy-mode-vi Y send -X copy-line
bind-key C-p paste-buffer
bind-key P paste-buffer
bind -T copy-mode-vi Escape send-keys -X cancel
ATTACKBOX_TMUX_CONF_EOF
tmux new -s main
