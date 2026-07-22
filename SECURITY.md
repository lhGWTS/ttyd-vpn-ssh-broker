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
- **Session reset is a separate, argv-validated mechanism — not a reopened
  ssh escape sequence.** `broker.sh` accepts an optional second argument that
  must be the exact literal string `reset` (anything else is rejected the
  same way a malformed IP is); if present, it kills the target's existing
  tmux session (via the same `SESS` name derivation already used for
  `has-session`/`new-session`) before falling through into the unchanged
  existing attach-or-create logic. This does not touch `session.sh`'s
  `-e none` and does not reopen any ssh-level escape processing. It also
  doesn't cross a new trust boundary: anyone holding the single shared
  credential can already forcibly steal any session via `attach-session -d`
  (see above), so "kill, then start fresh" is strictly less powerful than
  what's already possible today — the only new effect is that in-progress
  remote work/scrollback in the killed session is discarded rather than
  preserved. The browser-side checkbox that drives this defaults to
  unchecked and is labeled as destructive. `thmctl reset <ip>` offers the
  same kill capability to the operator directly, deliberately without the
  auto-reopen the browser-facing path does. (Implementation note: the first
  version of `thmctl reset` passed the target session name to `su ... -c`
  as a positional argument, which silently became empty under the installed
  `su` and caused a full `tmux` server kill instead of a single session —
  caught live during testing, fixed by restricting the IP argument to
  `[0-9.]` and interpolating it directly into the `-c` string instead. No
  ongoing risk from this — noted here since it's a concrete example of why
  the argv-passing assumptions in this doc are worth re-verifying whenever
  `su`/`sh -c` invocations change.)

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
