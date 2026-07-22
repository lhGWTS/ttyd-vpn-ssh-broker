# TryHackMe AttackBox ttyd ブローカー — 構築まとめ

最終更新: 2026-07-10

ブラウザの HTML フォームから宛先 IP を入力すると、VPN 越しに TryHackMe の
AttackBox/ターゲットへ ttyd 経由の ssh でつながる仕組み。認証・TLS は前段の
Caddy、内部はサンドボックス化した ssh、という多層構成。ブラウザからの接続は
検証済み（稼働中）。

---

## 1. 全体アーキテクチャ

```
ブラウザ
  │  HTTPS + Basic認証
  ▼
Caddy(別コンテナ)
  ├─ /            … 宛先IP入力フォーム(form.html) を静的配信
  └─ /tty/*       … reverse_proxy → thm.incus:7681 (ttyd)
                     フォーム送信で /tty/?arg=<IP> へ遷移
  ▼
thm.incus コンテナ (Alpine 3.24, Incusブリッジ例: 10.0.0.X)
  openvpn(root, --disable-dco) ── tun0(THM VPN) を提供
  ttyd(ephemeral uid1000, -b /tty -a -W)
    └─ broker.sh   … ?arg のIPを RFC1918 厳格検証
        └─ tmux    … 宛先IPごとの永続セッション(切断後もssh維持)
            └─ bubblewrap … ssh を隔離(/root・認証情報を遮断, netns共有)
                └─ ssh root@<IP>  … パスワードは端末に対話入力
  ▼ (tun0 経由)
TryHackMe AttackBox / ターゲット
```

- 制御ノード(このリポジトリを実行するホスト)と `thm` は同じ Incus ブリッジ上の
  ピアという構成を想定。ホストに `incus`/`lxc` CLI が無い場合、**thm への経路は
  SSH(22) のみ**になる（`ssh root@thm.incus -i ./thm`, 各自の鍵を用意する）。

---

## 2. ファイル一覧

### thm.incus コンテナ内 `/opt/thm/`
| ファイル | 役割 |
|---|---|
| `thmctl` | 起動/停止オーケストレータ。`/usr/local/bin/thmctl` にシンボリックリンク |
| `broker.sh` | ttyd の実行コマンド。宛先IP検証 → tmux 起動 |
| `session.sh` | tmux 内で bubblewrap + ssh を実行 |
| `tmux.conf` | 永続セッション用設定(status off, destroy-unattached off 等) |
| `caddy/form.html` | 宛先IP入力フォーム(Caddy側へ配置する参照コピー) |
| `caddy/Caddyfile.snippet` | Caddy設定例(参照コピー) |
| `firewall.sh` | tcp/7681を`CADDY_IP`(既定10.0.0.10)のみ許可する冪等スクリプト。専用チェーン`THM_TTYD`に`ACCEPT`/`DROP`を持たせ、再実行しても重複しない。既定で apply→`rc-service iptables save`→`rc-update add iptables default`まで実行(`firewall.sh apply`で適用のみ) |

### thm.incus その他
| パス | 役割 |
|---|---|
| `/etc/init.d/thm` | OpenRC サービス(default runlevel に登録済み=自動起動) |
| `/root/thm.ovpn` | THM VPN 設定(認証情報埋め込み, ローテーション制) |
| `/etc/iptables/rules-save` | `firewall.sh`が保存するiptables永続化ファイル(`iptables`サービスが起動時にrestore) |

### 制御ノード側(このリポジトリ)
| ファイル | 役割 |
|---|---|
| `ansible/roles/thm_broker/files/*` | 上表のthm.incus側ファイル一式の原本(このAnsibleロールがそのままコピーする) |
| `ansible/` | `make rebuild` でthm.incus相当のコンテナを再構築するための一式 |
| `ARCHITECTURE.md` | 本ファイル |

接続用のSSH鍵(`thm`)や、実際に発行された`.ovpn`はこのリポジトリには含まれない
（`thm_ovpn_src`で外部から渡す設計。[README](ansible/README.md#the-vpn-secret)参照)。
各自の環境に合わせて自分の鍵・自分の`.ovpn`を用意すること。

---

## 3. 動作フロー

1. ブラウザで Caddy のホストへアクセス → Basic認証。
2. フォームで宛先IP(例 `10.10.123.45`)を入力・送信 → JS が `/tty/?arg=<IP>` へ遷移。
3. Caddy が `/tty/*` を thm.incus:7681(ttyd) へ中継。ttyd(`-a`)が `?arg` の値を
   `broker.sh` の引数として渡す。
4. `broker.sh` がIPを検証(RFC1918のみ)し、`thm_<IP>` という名前の tmux
   セッションを起動(既存なら再アタッチ)。
5. tmux 内で `session.sh` が bubblewrap で隔離した ssh を起動。
6. 端末に `root@<IP>'s password:` が出るので、THMルームのrootパスワードを貼り付け。
7. 以降は通常の ssh セッション。ブラウザを閉じても tmux 内で ssh は生存し、
   同じIPで再接続すると復帰する。

---

## 4. 運用コマンド (`thmctl`, root で実行)

```sh
thmctl start        # VPN + ttyd をまとめて起動
thmctl stop         # 停止
thmctl restart      # 再起動
thmctl status       # 稼働状況 + tun0 + tmuxセッション一覧
thmctl vpn-start | vpn-stop | web-start | web-stop   # 個別制御
```

- 自動起動: OpenRC サービス `thm`(default runlevel)。`rc-service thm start/stop/status` でも可。
- **VPN認証情報の失効時**: `/root/thm.ovpn` を新しい .ovpn に
  差し替えて `thmctl restart`。

---

## 5. セキュリティモデル

- **権限分離**: root で動くのは openvpn のみ。ttyd/tmux/bubblewrap/ssh は
  ephemeral(uid1000)。ttyd の `-u/-g` で降格。
- **認証情報の遮断**: `/root`(0700) に加え、bubblewrap が `/root` を一切 bind
  しないため、万一 ssh セッション側が侵害されても VPN 認証情報は読めない。
- **入力検証(実機で確認済み)**: `broker.sh` は宛先を厳格な dotted-quad +
  RFC1918(10/8, 172.16/12, 192.168/16) に限定。`;reboot` / スペース /
  `-oProxyCommand=` / `$(id)` / 余分な引数 をすべて拒否。加えて `root@<IP>`
  前置で ssh オプション注入を無効化。
- **サンドボックス recipe(ネストIncus対応)**: `--unshare-user --unshare-ipc
  --unshare-uts --unshare-cgroup --proc /proc`(PID名前空間は付けない=procfs
  マウント制約回避)、`--share-net`(VPN到達に必要)、home は tmpfs。
- **パスワードの扱い**: 対象rootパスワードは端末に対話入力。URL・argv・環境変数・
  ファイルのいずれにも残らない。
- **ssh エスケープシーケンスの無効化(2026-07-22)**: `session.sh` は `setsid`
  を使わない(`/dev/tty` からパスワードを読ませるため)ので、ブラウザ側の
  キー入力は ssh の制御端末にそのまま届く。つまり `~`(行頭)から始まる ssh の
  エスケープシーケンスも素通しになっていた。特に `~C`(`-D`/`-L`/`-R` を
  対話的に追加するコマンドライン)は、`--share-net` によりVPNトンネルと
  同じネットワーク名前空間を共有しているため、動的SOCKSプロキシ等を張られると
  `broker.sh` が検証した1つの宛先IPを飛び越えて任意の到達可能ホストへ
  ピボットできてしまう恐れがあった。**実機確認の結果、インストール済みの
  OpenSSH(10.3p1)では`~C`はOpenSSH 9.2以降のデフォルトで既に無効**
  (`EnableEscapeCommandline=yes`が無いと有効化されない)であり、現状は
  exploit不可能だったが、これは本プロジェクトの意図した対策ではなく
  上流のデフォルト値に依存した偶然の安全性だったため、`ssh -e none` を
  明示的に追加してエスケープシーケンス全体を無効化した(このブローカーの
  用途ではオペレーター自身が `~C`/`~.` 等を使う必要は一切無い)。
- **認証は Caddy に一本化**(ユーザー判断)。ttyd 自体は無認証で 0.0.0.0:7681。
  → 対応済み: thm.incus に `iptables` を導入し、`firewall.sh`(専用チェーン
    `THM_TTYD`)で tcp/7681 を Caddy のIP(`10.0.0.10`)からのみ許可・他は
    DROP(2026-07-12)。同一ブリッジ上の他コンテナから Caddy を迂回した
    直アクセスは遮断済み(同一ブリッジ上の別ホストから直接 curl して
    302→タイムアウトに変化することを確認)。ルールは `rc-service iptables save`
    で永続化し、`iptables` を default ランレベルに追加(`thm` サービスは元々
    `after firewall` 依存があり、`iptables` init script が `provide firewall`
    のため起動順も正しい)。`firewall.sh`は再実行しても冪等(チェーンを
    毎回作り直すため、`CADDY_IP` を変えて再適用しても重複ルールが残らない)。

---

## 6. 環境の制約と回避策(解消済み・記録として残す)

- 構築初期には **CDN egress が遮断**されており(親ホスト/Incusのegressポリシー)、
  thm から `apk update`/`apk add` は timeout していた。TCPハンドシェイクやDNSは
  通るが持続HTTP転送が止まる、という症状。
- 当時の回避策: 別ホスト(CDNに到達できる制御ノード)で `.apk` を `curl` 取得 →
  `scp` で thm へ転送 → `apk add ./*.apk`。この方式で **bubblewrap** と
  **tmux(+libevent)** をインストールした。
- **2026-07-22 時点で CDN egress は復旧しており、thm から直接
  `apk update`/`apk add` が通ることを確認済み**。したがって上記の回避策は
  現在は不要 — 通常どおり `apk add <package>` で足りる。Ansibleロール
  (`thm_packages`)もこの前提(通常のapk到達性)で最初から設計されているため、
  変更は不要。egressポリシーが環境によって変わる可能性は残るので、同じ症状
  (TCP/DNSは通るがHTTP転送だけ止まる)に遭遇した場合の参考として本節は残す。
- 参考: 非特権ユーザー名前空間は動作する(bubblewrap が setuid 無しで隔離可能)。

---

## 7. Caddy 側(別コンテナ)の設定

`/opt/thm/caddy/` の参照ファイルを Caddy コンテナへ配置:
1. `form.html` を file_server ルートへ(例 `/srv/thm/index.html`) → `/` で表示。
2. `Caddyfile.snippet` を追記。要点:
   - `basicauth` で単一利用者認証 + 自動TLS。
   - `handle /tty/* { reverse_proxy thm.incus:7681 }`(ttyd は `-b /tty`。
     `handle_path` でプレフィックスを剥がさないこと)。
   - websocket は Caddy が自動アップグレード。

---

## 8. 検証済み事項

- VPN 起動で tun0 取得(例: `<tun0アドレス>/18`)。ターゲット網へ tun0 経由で到達可
  (`<ターゲットレンジ> via … dev tun0` 等、THM側が払い出すレンジはルーム/サブスクリプション
  によって変わる)。
- broker の入力検証(拒否/許可)、VPN未起動検知。
- bubblewrap 隔離: サンドボックス内から `/root`・VPN認証情報が不可視、ネットワーク共有。
- サンドボックス内 ssh がネットワーク越しに認証段階まで到達、対話パスワードプロンプト表示。
- ttyd が `/tty` ベースパスで配信・token 200・認証(オン時401/オフ時200)。
- tmux 永続化: クライアント切断後も `thm_<IP>` セッションと ssh が生存。
- OpenRC サービス経由の起動(`rc-service thm start`)。
- **ブラウザからの接続(エンドツーエンド)成功**。

---

## 9. 未対応・保留(任意)

### コードレビュー指摘 → 2026-07-12 適用済み
1. 〔中〕`session.sh` の TERM 問題 → `--setenv TERM xterm-256color` に固定(適用済)。
2. 〔中〕`thmctl stop`/`restart` の tmux サーバ残留 → `web_stop` に ephemeral の
   `tmux kill-server` を追加(適用済。`status()`と同じ`su ephemeral`パターン)。
3. 〔低〕ssh キープアライブ無し → `-o ServerAliveInterval=30 -o ServerAliveCountMax=4`
   を追加(適用済)。
4. 〔追加〕`broker.sh` のIP検証を先行ゼロ拒否に厳格化(8進数誤解釈対策, 適用済)。
5. 〔追加〕`firewall.sh` に `-i lo -j ACCEPT` を追加し、コンテナ内 loopback
   ヘルスチェックを許可(Caddy IP限定は維持, 適用済)。

上記はいずれも `ansible/roles/thm_broker/files/` 側に反映済み。`make rebuild`
または個別ファイルの再配置→`firewall.sh`再適用→`thmctl restart`で本番反映し、
loopback疎通・遮断維持・再接続でのセッション生成を実機確認済み。

### ターゲットWebのブラウザ閲覧(保留中)
- 目的: ターゲットの HTTP/HTTPS をブラウザで見る。thm は tun0 でターゲットへ
  直接到達できるため、AttackBox 側 socat 中継は不要。
- 課題: 試したサンプルルームのターゲットは**ルート絶対パス**を使うため
  `/http/` サブパスでは崩れる。標準 Caddy は本文書き換え不可。
- 選択肢(未決): 方式A(/http維持 + nginx `sub_filter` 書き換え, thmにnginxサイドロード)
  / 方式B(ターゲットをルート配信 + 管理UIを予約プレフィックスへ; 最も堅牢)
  / 方式C(SOCKS + ブラウザ設定; 最も忠実だがURL一本で完結しない)。
- ネット到達確認済み(`?arg=`本体は完成・稼働)。再開時に方式を選んで実装。

---

## 10. メモ(セッション永続化の設計判断)

- ttyd クライアントは接続パラメータを `window.location.search` からのみ読む
  (`ws = base + "/ws" + location.search`)。IPをパスに置いてもwsに乗らないため、
  宛先受け渡しは `?arg=` 方式を採用(最もシンプルで ttyd の設計に整合)。
- tmux はサンドボックスの**外側**に配置(bwrap は接続ごとに tmpfs が新規のため、
  内側だと再接続でセッション共有できない)。層順は ttyd → tmux → bwrap → ssh。

---

## 11. バックアップについて

このリポジトリの `ansible/roles/thm_broker/files/` が `/opt/thm/` 本体一式の
原本であり、`make rebuild` でいつでも再構築できる。それとは別に、稼働中の
thm.incus上でスクリプトを直接編集した場合は、このリポジトリ側が古くなるため、
`scp` 等で変更を取り込んでから再デプロイに反映すること(自動同期はしていない)。
`caddy/form.html` と `caddy/Caddyfile.snippet` は Caddy コンテナ側への配置物
のため、Caddy側の設定変更もあわせて手動で反映が必要。
