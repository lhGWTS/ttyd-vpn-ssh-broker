#!/bin/sh
# session.sh <target-ip>
#
# Runs inside a persistent tmux session (see broker.sh). Confines the ssh client
# with bubblewrap and connects to the AttackBox. Invoked only with an IP that
# broker.sh has already strictly validated.
set -u

TARGET="${1:?target ip required}"

# Override if you fork this repo and want your own tmux.conf served instead.
ATTACKBOX_TMUX_URL="${ATTACKBOX_TMUX_URL:-https://raw.githubusercontent.com/lhGWTS/ttyd-vpn-ssh-broker/main/attackbox/tmux.conf}"

printf '[broker] paste the target root password when prompted.\r\n\r\n'
printf '[broker] once connected, for a nicer tmux setup (needs AttackBox internet egress):\r\n'
printf '[broker]   curl -fsSL %s -o ~/.tmux.conf && tmux new -s main\r\n\r\n' "$ATTACKBOX_TMUX_URL"

# Sandbox notes:
#  * No --unshare-pid: nesting inside an unprivileged Incus container forbids
#    mounting a fresh procfs together with a new pid namespace, so we keep the
#    caller's pid ns and mount a fresh /proc (verified working here).
#  * No --new-session: ssh reads the password from the controlling terminal
#    (/dev/tty); setsid would detach it. Kernel TIOCSTI is disabled by default,
#    and each tmux pane is its own pty, so the risk is minimal.
#  * --share-net: the VPN tunnel lives in the shared network namespace.
#  * /root and every credential are simply never bound in -> unreadable.
#  * -e none: disables ssh's client-side "~" escape sequences entirely. Since
#    we never setsid, the browser user's keystrokes reach ssh's controlling
#    tty directly, so escapes are otherwise live. OpenSSH 9.2+ already
#    disables ~C (the one that can add -D/-L/-R forwards at runtime) by
#    default, which matters here because --share-net means any such forward
#    would reach far beyond the one broker.sh-validated $TARGET -- but that's
#    an upstream default we shouldn't depend on staying that way. No escape
#    sequence has a legitimate use in this broker, so turn off the whole
#    class rather than rely on -C alone being off.
exec bwrap \
  --unshare-user --unshare-ipc --unshare-uts --unshare-cgroup \
  --ro-bind /usr /usr \
  --ro-bind /bin /bin \
  --ro-bind /lib /lib \
  --ro-bind /sbin /sbin \
  --ro-bind /etc/ssl /etc/ssl \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --ro-bind /etc/passwd /etc/passwd \
  --ro-bind /etc/hosts /etc/hosts \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --tmpfs /home \
  --dir /home/ephemeral \
  --setenv HOME /home/ephemeral \
  --setenv TERM xterm-256color \
  --chdir /home/ephemeral \
  --share-net \
  --die-with-parent \
  -- ssh \
       -e none \
       -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null \
       -o GlobalKnownHostsFile=/dev/null \
       -o ConnectTimeout=15 \
       -o ServerAliveInterval=30 \
       -o ServerAliveCountMax=4 \
       root@"$TARGET"
