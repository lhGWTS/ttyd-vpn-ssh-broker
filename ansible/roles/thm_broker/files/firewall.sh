#!/bin/sh
# firewall.sh - restrict tcp/TTYD_PORT (ttyd) to the Caddy container only.
#
# Keeps its rules in a dedicated INPUT-jump chain (THM_TTYD) so the script is
# idempotent: re-running it (e.g. after CADDY_IP changes) rebuilds the chain
# instead of stacking duplicate ACCEPT/DROP rules. Everything else (ssh, the
# THM VPN on tun0, etc.) is untouched.
#
#   firewall.sh          apply the rules, save them, and enable iptables at boot
#   firewall.sh apply    apply only, skip save/enable (for testing changes)
set -u

CADDY_IP="${CADDY_IP:-10.0.0.10}"
TTYD_PORT="${TTYD_PORT:-7681}"
MODE="${1:-full}"

iptables -N THM_TTYD 2>/dev/null || iptables -F THM_TTYD
iptables -C INPUT -p tcp --dport "$TTYD_PORT" -j THM_TTYD 2>/dev/null \
  || iptables -A INPUT -p tcp --dport "$TTYD_PORT" -j THM_TTYD
iptables -A THM_TTYD -i lo -j ACCEPT
iptables -A THM_TTYD -s "$CADDY_IP" -j ACCEPT
iptables -A THM_TTYD -j DROP

echo "[firewall] tcp/$TTYD_PORT restricted to $CADDY_IP (THM_TTYD chain)"
iptables -L THM_TTYD -n -v

[ "$MODE" = "apply" ] && exit 0

rc-service iptables save
rc-update add iptables default 2>/dev/null
echo "[firewall] saved and enabled at boot"
