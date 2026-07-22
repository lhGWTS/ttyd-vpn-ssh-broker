# Security

## Reporting a vulnerability

If you find a security issue in this project, please open a GitHub issue.
Since this is a small personal-scale tool rather than a maintained product
with an SLA, there's no formal disclosure program — a public issue is fine
for anything that isn't actively being exploited against a live deployment;
for anything more sensitive, use GitHub's private vulnerability reporting on
this repo if enabled, or contact the maintainer directly.

## Threat model

This broker assumes:
- The operator trusts whoever can authenticate through the front-end proxy
  (Caddy's basic auth in the reference setup) — that's a single shared
  credential, not per-user accounts. Anyone with it has full access to
  whatever RFC1918 targets the VPN can reach.
- The browser-side user is **not** trusted to run arbitrary commands on the
  broker host itself, only to reach the VPN'd target over ssh. That's why
  tmux runs deny-by-default and bubblewrap strips out `/root` and the VPN
  credentials from the sandboxed ssh session — see the security model section
  in the top-level [`README.md`](README.md) and the design rationale in
  [`ARCHITECTURE.md`](ARCHITECTURE.md).
- ttyd itself ships with no authentication of its own; it must sit behind an
  authenticating reverse proxy (or the firewall rule / `TTYD_CRED` fallback
  needs to be used instead) before it's reachable from anywhere untrusted.
- **ssh's client-side escape sequences are disabled** (`-e none` in
  `session.sh`). Without it, the browser user's raw keystrokes reach ssh's
  controlling tty directly (no `setsid` in between), so `~`-prefixed escapes
  would be live — notably `~C`, which can add a `-D`/`-L`/`-R` port forward at
  runtime. Since bwrap runs with `--share-net`, such a forward would reach
  anything on the shared network namespace, not just the one `broker.sh`-
  validated target. OpenSSH 9.2+ already disables `~C` by default, but that's
  an upstream default this project shouldn't rely on staying true, so it's
  disabled explicitly.

## Known limitations

- **No browser-clipboard copy via tmux.** ttyd 1.7.7's bundled xterm.js has no
  OSC 52 handler, so nothing in `tmux.conf` can make a tmux copy reach the
  browser's OS clipboard. The practical workaround (Shift+drag for native
  browser selection, then Ctrl+Insert) is documented in `attackbox/tmux.conf`
  and `attackbox/paste-into-ttyd.sh`. A client-side userscript fix and an
  upstream ttyd patch both exist but aren't shipped here — see the comments
  in those files if you want to go further.
- **Passwords are typed interactively by design**, not stored or automated.
  This is intentional (nothing sensitive ever touches disk/argv/env), but it
  means this tool doesn't do unattended/scripted access.
- **Single shared credential at the proxy layer** (see threat model above) —
  this isn't a multi-user access-control system. If you need per-user
  auditing/RBAC, look at a dedicated bastion/PAM project instead (Warpgate,
  JumpServer, Teleport, Apache Guacamole are all reasonable fits depending on
  your scale).
