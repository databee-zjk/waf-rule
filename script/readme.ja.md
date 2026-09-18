# waf-rule/script — 使い方

クローラの公開IPを取得し、AWS WAF の IPSet に反映する。

```
<取得スクリプト> | ./waf-ipset.sh replace -f - --IPSET_NAME=<名前> --apply
```

左が「IPを取ってくる」、右が「IPSetに書く」。それだけ。

---

## 導入（初回のみ）

### 1. AWS側の準備

主体ごとに IPSet を作る（**スクリプトは IPSet を作らない**。既存のものを操作する）。

| 必要なもの | 内容 |
|---|---|
| IPSet | **IPv4版**。主体ごとに1つ（例: `google-list`, `bing-list`） |
| IAM権限 | `wafv2:ListIPSets` / `wafv2:GetIPSet` / `wafv2:UpdateIPSet` |

### 2. config.sh を編集

```bash
AWS_PROFILE_NAME="prod"          # 使用するプロファイル
AWS_REGION="ap-northeast-1"      # CLOUDFRONT の場合は us-east-1
```

### 3. waf-ipset.sh の設定を確認

```bash
IPSET_SCOPE="REGIONAL"           # CloudFront配下なら CLOUDFRONT
```

### 4. 接続確認

```bash
./waf-ipset.sh list --IPSET_NAME=google-list
```

一覧が出れば準備完了。

---

## 日常の使い方

### IPを見るだけ（AWSに接続しない）

```bash
./get-google-ip.sh              # 最新のGoogleクローラIP
./get-bing-ip.sh                # Bing
./get-openai-ip.sh              # OpenAI（既定は検索用のみ）
./get-claude-ip.sh              # Claude

./get-google-ip.sh > google.txt # ファイルに保存
./get-google-ip.sh --all        # その主体の全取得元
./get-google-ip.sh --list       # 取得元の一覧を見る
./get-google-ip.sh --only google-crawler   # 1つだけ
```

### IPSetを操作する

```bash
./waf-ipset.sh list --IPSET_NAME=google-list           # 中身を見る
./waf-ipset.sh add 203.0.113.0/24 --IPSET_NAME=manual-list --apply   # 1件追加
./waf-ipset.sh del 203.0.113.0/24 --IPSET_NAME=manual-list --apply   # 1件削除
```

### 取得して反映する

```bash
# まず模擬実行（--apply なし）で差分を確認
./get-google-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=google-list

# 問題なければ --apply を付けて実行
./get-google-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=google-list --apply
```

**`--apply` を付けない限り書き込まれない。** 先に何が起きるか見られる。

---

## 定期実行（crontab）

```crontab
# 毎日1回。主体ごとに時間をずらす。--pipe でEnter待ちを無効化。
5  4 * * * cd /path/to/script && ./get-google-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=google-list --apply --pipe >> /var/log/waf-ipset.log 2>&1
15 4 * * * cd /path/to/script && ./get-bing-ip.sh   | ./waf-ipset.sh replace -f - --IPSET_NAME=bing-list   --apply --pipe >> /var/log/waf-ipset.log 2>&1
25 4 * * * cd /path/to/script && ./get-openai-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=openai-list --apply --pipe >> /var/log/waf-ipset.log 2>&1
35 4 * * * cd /path/to/script && ./get-claude-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=claude-list --apply --pipe >> /var/log/waf-ipset.log 2>&1
```

- `--pipe` を付けないと Enter 待ちで止まる
- `2>&1` でログも残す。**異常だけ見るなら `grep ERROR /var/log/waf-ipset.log`**
- 1日1回で十分（Googleは毎日更新、Bingは2年以上変化なし）

### 終了コードで監視する

| コード | 意味 |
|---|---|
| 0 | 反映した |
| 3 | 変更なし（正常。毎日走らせれば大半はこれ） |
| 1 | 取得失敗・検査不合格・書き込み失敗 |
| 2 | 引数・設定の誤り |

上流（取得側）の成否は `PIPESTATUS` で見る。

---

## 設定

### 設定の場所

| 設定 | 場所 |
|---|---|
| `AWS_PROFILE_NAME` / `AWS_REGION` / `LOG_DIR` | `config.sh` |
| `IPSET_SCOPE` / `IPSET_NAME` / `MIN_PREFIX_LEN` / `MAX_ADDRESSES` / `MAX_SHRINK_PERCENT` | `waf-ipset.sh` の設定区 |
| 取得元のURL | 各取得スクリプトの `SOURCES` |
| curl のタイムアウト・User-Agent | `lib/crawler-ip.lib.sh` |

### コマンドラインで上書きする

**設定項目名がそのまま引数名になる。**

```bash
./waf-ipset.sh list --IPSET_NAME=other-list
./waf-ipset.sh list --IPSET_SCOPE=CLOUDFRONT --AWS_REGION=us-east-1
./waf-ipset.sh add 203.0.113.0/24 --AWS_PROFILE_NAME=prod --apply
```

一覧は `--help` で表示。設定区に無い名前はエラーになる。

### 取得元URLを変更する

各取得スクリプトの先頭にある。**Google は 2026-03 に実際にURLを変更した実績がある**ので、
404や301で失敗したら `../ip-*.md` の出典を確認してここを直す。

```bash
declare -A SOURCES=(
    [bing.url]="https://www.bing.com/toolbox/bingbot.json"
    [bing.desc]="Bingbot（Copilot / Yahoo / DuckDuckGo も同基盤）"
)
```

---

## 書き込み前の安全装置

`waf-ipset.sh` は、上流が何であっても以下を検査してから書き込む。

| 検査 | 内容 |
|---|---|
| CIDR形式 | ネットワークアドレスであること（`203.0.113.5/24` は拒否し正しい形を提示） |
| 広すぎる指定 | `/16` より広いものを拒否（`MIN_PREFIX_LEN`） |
| 空の入力 | 上流が失敗して何も出さなかった場合、書き込まずに中止 |
| **件数の急減** | `replace` で30%を超えて減るなら中止（`MAX_SHRINK_PERCENT`） |
| 件数の上限 | AWS上限の10,000件を超えるなら中止 |

**件数の急減検査が、上流の異常を検知する最後の砦。**
正当な減少だと確認できたら `--MAX_SHRINK_PERCENT=100` を付けて再実行する。

---

## エラーが出たら

**aws CLI や curl の生のエラー文をそのままログに出す。** 握りつぶさない。

| ログに出るもの | 見るところ |
|---|---|
| `AccessDeniedException` | IAM権限。必要なのは `ListIPSets` / `GetIPSet` / `UpdateIPSet` |
| `ExpiredToken` | `aws sso login` 等で認証を取り直す |
| `IPSet が見つかりません` | 名前 / `IPSET_SCOPE` / `AWS_REGION` の組み合わせ |
| `HTTPステータスが 200 ではありません: 404` | 公開元がURLを変更した。`SOURCES` を直す |
| `curl の実行に失敗しました（終了コード: 6）` | DNS。cron は対話シェルと環境変数が違う点に注意 |
| `curl の実行に失敗しました（終了コード: 7）` | プロキシ・ファイアウォール |
| `件数が大きく減少します` | 上流の異常か、正当な減少か確認してから再実行 |

エラー行には原因と対処を併記してある。まずそれを読む。

---

## 未対応

| 項目 | 内容 |
|---|---|
| **IPv6** | 取得は `--ipv6` でできるが、反映は未対応（`waf-ipset.sh` はIPv4専用）。Googleは約1,000件公開している |
| **UA別の出し分け** | IPだけでは不可能。ClaudeBot は3種のUAが分かれていないため、WAFルール側で文字列条件との併用が必要 |
| **Gemini / Copilot** | 専用IPリストが存在しない。Gemini は Google、Copilot は Bing のIPに含まれる（`../ip-gemini.md` / `../ip-copilot.md`） |

---

## 動作環境

- bash **4.4 以上**（起動時に確認し、古ければ明確に停止する）
- `curl`（取得側）/ `aws` CLI v2（反映側）
- `jq` は不要

Amazon Linux 2 / CentOS 7 の bash は 4.2 のため動かない。
Amazon Linux 2023 / Ubuntu 20.04+ / Debian 10+ は問題ない。

---

## 生成物

`analysis/update-<IPSet名>.json` … AWSへ送信したJSON。毎回上書きし、履歴は残さない。
実行記録はファイルに残さず標準エラーへ出すので、crontab のログで確認する。

---
[zjk 2026-09-18 AI補助]
