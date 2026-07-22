# THM AttackBox ttyd broker — Ansible

Reproduces the hand-built broker that lives in an Alpine container (`thm.incus`
in the examples below), so it can be rebuilt from a blank container if it's
ever lost. See `../ARCHITECTURE.md` for the architecture and rationale.

## What it builds

A browser → Caddy (TLS + basic auth) → ttyd → tmux → bubblewrap → ssh path that
reaches TryHackMe AttackBoxes over an OpenVPN tunnel. This playbook provisions
**only the thm.incus side**; the Caddy container is separate (its reference files
are shipped to `/opt/thm/caddy/` so you can copy them onto Caddy by hand).

Layers configured on thm:

- runtime packages (bubblewrap, tmux, ttyd, openvpn, iptables, openssh, sshpass …)
- the `ephemeral` uid 1000 web user
- `/opt/thm/{thmctl,broker.sh,session.sh,tmux.conf,firewall.sh}` + `thmctl` symlink
- the THM `.ovpn` VPN config (a secret — supplied out of band, see below)
- the `thm` OpenRC service (enabled at boot); sshd/crond/iptables/local also enabled
- `firewall.sh` — ttyd (tcp/7681) reachable only from the Caddy IP
- `hidepid=2` on `/proc` via `/etc/local.d/hidepid.start`

## Requirements

```sh
pip3 install ansible-core
ansible-galaxy collection install community.general   # for the apk module
```

Connectivity matches a manual `ssh root@thm.incus -i ./thm`; see `inventory.ini`
and supply your own key.

## Usage

thm has no python3 by default, and Ansible's file/service modules need it. So the
run is three stages — add python3, provision, remove python3 again (python must
not be reachable from inside the bwrap sandbox, which ro-binds `/usr`):

```sh
make rebuild        # bootstrap + provision + teardown, in order
```

or step by step:

```sh
ansible-playbook -i inventory.ini bootstrap.yml    # install python3 (temporary)
ansible-playbook -i inventory.ini site.yml         # build everything
ansible-playbook -i inventory.ini teardown.yml     # remove python3 again
```

Dry run (after bootstrap, while python3 is present):

```sh
make check          # site.yml --check --diff
```

## The VPN secret

The `.ovpn` holds rotating embedded credentials and is **not** in this repo. Two
options:

- set `thm_ovpn_src` (e.g. `-e thm_ovpn_src=~/secrets/thm.ovpn`) to have the role
  install it to `{{ thm_ovpn_path }}` (0600, root), or
- leave it empty and drop the file in by hand; the web tier still starts, and
  `thmctl restart` picks up a replaced config.

When THM rotates the creds: replace the file and `thmctl restart`.

## Package versions (prod parity)

apk is assumed to work in the rebuild environment. Current prod versions, if you
want byte-for-byte parity (pin in `thm_packages` or group_vars):

```
bubblewrap 0.11.2   tmux 3.6b   libevent 2.1.13
iptables 1.8.13 (+iptables-openrc)   openvpn 2.7.3 (+openvpn-openrc)
ttyd 1.7.7   openssh   sshpass
```

## Layout

```
inventory.ini            thm.incus over ssh (key: your own, see inventory.ini)
bootstrap.yml            stage 0: install python3 (raw, no python needed)
site.yml                 stage 1: run the thm_broker role
teardown.yml             stage 2: remove python3 (raw)
Makefile                 `make rebuild` chains the three
roles/thm_broker/
  defaults/main.yml      all tunables (ports, uid, caddy ip, packages, paths)
  tasks/main.yml         the build
  handlers/main.yml      restart thm / reload firewall / remount hidepid
  files/                 thmctl, broker.sh, session.sh, tmux.conf, firewall.sh,
                         hidepid.start, thm.initd, caddy/{form.html,Caddyfile.snippet}
```
