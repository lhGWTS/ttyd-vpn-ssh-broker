# ttyd-vpn-ssh-broker

A self-hosted, browser-based access broker: point a browser at a form, type a
private-network IP, and get a persistent SSH terminal to it — reached through
an OpenVPN tunnel, brokered by [ttyd](https://github.com/tsl0922/ttyd), and
isolated with [bubblewrap](https://github.com/containers/bubblewrap). It was
built for reaching [TryHackMe](https://tryhackme.com) AttackBoxes from any
device with just a browser, but the broker itself has no TryHackMe-specific
logic — swap in your own OpenVPN config and it'll jump to any RFC1918 target
your VPN can reach.

```
browser
  │  HTTPS + basic auth
  ▼
Caddy                              (TLS termination + auth, separate host)
  ▼
ttyd                               (web terminal)
  └─ broker.sh                     (validates the destination IP: RFC1918 only)
      └─ tmux                      (persistent session per target, survives disconnects)
          └─ bubblewrap             (sandboxes the ssh client: no /root, no creds)
              └─ ssh root@<target>  (password typed interactively, never stored)
  ▲
  └─ OpenVPN tunnel into the target's private network
```

Full write-up (architecture, threat model, design decisions) is in
[`ARCHITECTURE.md`](ARCHITECTURE.md) — written in Japanese.

## What you need to bring yourself

This repo does **not** include, and will never include:
- Your own OpenVPN `.ovpn` config (a secret with embedded, often-rotating
  credentials — see [`ansible/README.md`](ansible/README.md#the-vpn-secret)
  for how to supply it out-of-band via `thm_ovpn_src`)
- An SSH key to reach the container you deploy this into
- A Caddy (or other reverse proxy) host in front of it for TLS + auth — ttyd
  itself is unauthenticated by design; see the security model below

## Quickstart

```sh
cd ansible
ansible-playbook -i inventory.ini bootstrap.yml   # temp python3 for provisioning
ansible-playbook -i inventory.ini site.yml        # build the broker
ansible-playbook -i inventory.ini teardown.yml     # remove python3 again
# or just: make rebuild
```

See [`ansible/README.md`](ansible/README.md) for full details, variables, and
package-version pinning.

`attackbox/` has an optional `.tmux.conf` + paste-transfer helper for running
tmux *inside* the target itself (for multi-pane convenience once you're
connected) — see the comments in `attackbox/tmux.conf` for what it does and,
importantly, what it can't do (browser clipboard copy is a `ttyd`/xterm.js
limitation, not something any tmux config can fix — the file explains the
actual workaround).

## Security model

- **Privilege separation**: only OpenVPN runs as root. ttyd/tmux/bubblewrap/
  ssh all run as an unprivileged `ephemeral` user (ttyd drops privileges via
  `-u`/`-g`).
- **Credential isolation**: bubblewrap never binds in `/root`, so even a
  compromised ssh session inside the sandbox can't read the VPN credentials.
- **Strict input validation**: `broker.sh` only accepts dotted-quad RFC1918
  addresses (10/8, 172.16/12, 192.168/16); shell metacharacters, extra
  arguments, and `-oProxyCommand=`-style ssh option injection are all
  rejected.
- **tmux is hardened deny-by-default**: tmux runs *outside* the bwrap sandbox,
  so a reachable `C-b :` command prompt would mean arbitrary `run-shell` —
  i.e. a sandbox escape. The shipped `tmux.conf` unbinds everything and
  allow-lists only mouse-wheel scrolling and passthrough to mouse-aware remote
  apps.
- **Passwords are typed interactively, never stored**: the target's root
  password never appears in a URL, argv, environment variable, or file.
- **ttyd itself is unauthenticated** (`0.0.0.0`, no `-c`) — auth is handled
  entirely by Caddy in front of it. If you deploy without a reverse proxy in
  front, put authentication back at the ttyd layer or firewall it off.
  `firewall.sh` additionally source-IP-restricts the ttyd port to the proxy
  host, so nothing on the same bridge network can bypass Caddy's auth
  directly.

## A note on scope

This tool only automates VPN/SSH access you're already authorized to use — it
doesn't circumvent authentication or bypass any access control. If you deploy
this against TryHackMe or any other platform, you're responsible for
complying with that platform's terms of service.

## License

MIT — see [`LICENSE`](LICENSE).

Issues and PRs welcome.
