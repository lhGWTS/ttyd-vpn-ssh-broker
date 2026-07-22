#!/bin/sh
# session.sh <target-ip>
#
# Runs inside a persistent tmux session (see broker.sh). Confines the ssh client
# with bubblewrap and connects to the AttackBox. Invoked only with an IP that
# broker.sh has already strictly validated.
set -u

TARGET="${1:?target ip required}"

printf '[broker] paste the target root password when prompted.\r\n\r\n'

# Sandbox notes:
#  * No --unshare-pid: nesting inside an unprivileged Incus container forbids
#    mounting a fresh procfs together with a new pid namespace, so we keep the
#    caller's pid ns and mount a fresh /proc (verified working here).
#  * No --new-session: ssh reads the password from the controlling terminal
#    (/dev/tty); setsid would detach it. Kernel TIOCSTI is disabled by default,
#    and each tmux pane is its own pty, so the risk is minimal.
#  * --share-net: the VPN tunnel lives in the shared network namespace.
#  * /root and every credential are simply never bound in -> unreadable.
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
       -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null \
       -o GlobalKnownHostsFile=/dev/null \
       -o ConnectTimeout=15 \
       -o ServerAliveInterval=30 \
       -o ServerAliveCountMax=4 \
       root@"$TARGET"
