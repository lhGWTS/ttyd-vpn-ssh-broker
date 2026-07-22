#!/bin/sh
# broker.sh <target-ip>
#
# ttyd's per-session entrypoint (started with `-a`, so the browser's ?arg=<ip>
# arrives here as "$1"). It validates the destination, requires the VPN, then
# hands off to a *persistent* tmux session that survives websocket disconnects.
#
# Layering:  ttyd -> broker.sh -> tmux (persistent, unprivileged) -> session.sh
#            -> bwrap (sandbox) -> ssh
#
# tmux lives OUTSIDE the sandbox on purpose: each bwrap gets a fresh tmpfs, so a
# tmux socket inside it could not be shared across reconnects. Keeping tmux here
# lets a dropped browser leave the ssh running; reconnecting to the same target
# re-attaches it. The target root password is typed into the terminal -- never in
# a URL, argv, env var or file.
#
# Runs unprivileged (ttyd drops to the ephemeral uid before exec'ing this).
set -u

export HOME=/home/ephemeral
TMUX_CONF=/opt/thm/tmux.conf
SESSION_CMD=/opt/thm/session.sh

die() { printf '\r\n\033[1;31m[broker] %s\033[0m\r\n' "$*"; sleep 4; exit 1; }

# --- validate the destination ------------------------------------------------
[ "$#" -eq 1 ] || die "expected exactly one destination (got $# arguments)"
TARGET="$1"

echo "$TARGET" | grep -Eq '^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$' \
  || die "not an IPv4 address: $TARGET"
OLDIFS=$IFS; IFS=.; set -- $TARGET; IFS=$OLDIFS
for o in "$@"; do
  [ "$o" -ge 0 ] 2>/dev/null && [ "$o" -le 255 ] 2>/dev/null || die "invalid octet: $o"
done
o1=$1; o2=$2
priv=no
[ "$o1" -eq 10 ] && priv=yes
[ "$o1" -eq 192 ] && [ "$o2" -eq 168 ] && priv=yes
[ "$o1" -eq 172 ] && [ "$o2" -ge 16 ] && [ "$o2" -le 31 ] && priv=yes
[ "$priv" = yes ] \
  || die "destination must be a private THM address (10/8, 172.16/12, 192.168/16): $TARGET"

# --- require the VPN tunnel --------------------------------------------------
ip link show tun0 >/dev/null 2>&1 \
  || die "VPN tunnel (tun0) is not up. Ask the operator to start it, then retry."

# --- persistent tmux session, one per target ---------------------------------
# Session name is derived from the (already strictly validated) IP.
SESS="thm_$(printf '%s' "$TARGET" | tr . _)"

if tmux -f "$TMUX_CONF" has-session -t "$SESS" 2>/dev/null; then
  # Existing live session: re-attach, detaching any stale/other client (-d) so
  # the window resizes to this browser.
  exec tmux -u -f "$TMUX_CONF" attach-session -d -t "$SESS"
else
  printf '\033[1;36m[broker] opening session to AttackBox %s over the THM VPN...\033[0m\r\n' "$TARGET"
  exec tmux -u -f "$TMUX_CONF" new-session -s "$SESS" "$SESSION_CMD $TARGET"
fi
