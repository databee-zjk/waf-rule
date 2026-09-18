# waf-rule/script

クローラの公開IPを取得し、AWS WAF の IPSet に反映する。

```
<取得スクリプト> | ./waf-ipset.sh replace -f - --arn=<ARN> --apply
       ↓                              ↓
   IPを出す                    IPSetに書く
```

---

## スクリプト一覧

| スクリプト | 入力 | 出力 |
|---|---|---|
| `get-google-ip.sh` | なし | Google のIP（CIDR、1行1件） |
| `get-bing-ip.sh` | なし | Bing のIP |
| `get-openai-ip.sh` | なし | OpenAI のIP |
| `get-claude-ip.sh` | なし | Claude のIP |
| `waf-ipset.sh` | CIDR一覧 + ARN | AWS WAF の IPSet を更新 |

取得系は AWS に接続しない。`waf-ipset.sh` は取得しない。

---

## 1. 取得する

```bash
./get-bing-ip.sh
```
→ 標準出力に CIDR が1行1件で出る。標準エラーに進捗。

```bash
./get-bing-ip.sh > bing.txt
```
→ ファイルには CIDR だけが入る（進捗は標準エラーなので混ざらない）

| オプション | 動作 |
|---|---|
| なし | 既定の取得元 |
| `--all` | その主体の全取得元 |
| `--ipv6` | IPv6 を出す |
| `--only <名前>` | 取得元を1つだけ |
| `--list` | 取得元の一覧を見る |

---

## 2. IPSet を操作する

対象は **ARN で指定する**（リージョン・スコープ・名前・IDが全部入っているため）。

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:123456789012:regional/ipset/名前/ID
```

| サブコマンド | 動作 |
|---|---|
| `list` | 現在の登録内容を表示 |
| `add <CIDR>` | 追加 |
| `del <CIDR>` | 削除 |
| `replace -f <ファイル>` | 全件置換 |
| `clear` | 全件削除して空にする |

**`--apply` を付けない限り書き込まない。** 付けなければ差分を表示するだけ。

---

## 3. パイプで繋ぐ

```bash
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=$ARN
```
→ 模擬実行。差分が出る。書き込まない。

```bash
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=$ARN --apply
```
→ 書き込む。

`-f -` が「標準入力から読む」の意味。

---

## 4. CloudFront と ALB の両方に入れる

WAF は CloudFront（グローバル）と ALB（リージョン）で設定場所が分かれている。
さらに IPv4 と IPv6 も別の IPSet になる。**同じIPリストを4箇所に入れることになる。**

```bash
./get-google-ip.sh        | ./waf-ipset.sh replace -f - --arn=$ARN_CF_V4  --apply
./get-google-ip.sh        | ./waf-ipset.sh replace -f - --arn=$ARN_ALB_V4 --apply
./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=$ARN_CF_V6  --apply
./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=$ARN_ALB_V6 --apply
```

ARN のリージョンとスコープは自動判別されるので、指定は ARN だけでよい。

---

## 5. cron に登録する

`crontab.sample` をコピーして使う。要点は3つ。

```crontab
WAF_DIR=/opt/waf-rule/script
WAF_LOG=/var/log/waf-ipset.log
ARN_ALB_V4=arn:aws:wafv2:ap-northeast-1:123456789012:regional/ipset/名前/ID

05 4 * * * cd $WAF_DIR && ./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=$ARN_ALB_V4 --apply --pipe >> $WAF_LOG 2>&1
```

1. **`--pipe` を必ず付ける**（付けないと Enter 待ちで止まる）
2. **`2>&1` でログに残す**（進捗もエラーも標準エラーに出る）
3. 対象ごとに5分ずらす（AWS の更新API は1秒1回まで）

異常だけ見る:
```bash
grep ERROR /var/log/waf-ipset.log
```

終了コード:

| コード | 意味 |
|---|---|
| 0 | 反映した |
| 3 | 変更なし（正常。毎日走らせれば大半はこれ） |
| 1 | 取得失敗・検査不合格・書き込み失敗 |
| 2 | 引数・設定の誤り |

---

## 6. すぐ試す

**全部自動で通す:**

```bash
./test-run.sh
```
→ 「空 → 書き込み → 照合 → 空」を一周し、手順ごとに OK/NG を表示する。
　 実行したコマンドも表示されるので、気になる手順だけコピペして再実行できる。

```bash
./test-run.sh --read
```
→ 読み取りだけ（AWSに書き込まない）

**1つずつ自分で確認する場合は `test.md` にコピペ用のコマンドが並べてある。**

### 手で1歩ずつ確認する最短コース

`$ARN` は自分の IPSet の ARN に置き換える。

```bash
# ① 今の中身を見る
./waf-ipset.sh list --arn=$ARN
```

```bash
# ② 空にする
./waf-ipset.sh clear --arn=$ARN --apply
```

```bash
# ③ 空になったか確認（登録件数: 0 件 と出る）
./waf-ipset.sh list --arn=$ARN
```

```bash
# ④ 取得だけしてみる（AWSに触らない）
./get-bing-ip.sh
```

```bash
# ⑤ 書き込まずに差分を見る
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=$ARN
```

```bash
# ⑥ 実際に書き込む
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=$ARN --apply
```

```bash
# ⑦ 入ったか確認
./waf-ipset.sh list --arn=$ARN
```

```bash
# ⑧ 取得元と1件単位で一致するか照合（★これが通れば本物）
./get-bing-ip.sh 2>/dev/null | sort > expect.txt && ./waf-ipset.sh list --arn=$ARN --pipe 2>/dev/null | sort > actual.txt && diff expect.txt actual.txt && echo "★ 完全一致"
```

```bash
# ⑨ もう一度⑥を流す → 「変更はありません」＋終了コード3 になる
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=$ARN --apply ; echo "終了コード=$?"
```

```bash
# ⑩ 片付け
./waf-ipset.sh clear --arn=$ARN --apply && rm -f expect.txt actual.txt
```

---

## 7. 書き込み前の検査

`waf-ipset.sh` は上流が何であっても、書き込む前に以下を確認する。

| 検査 | 内容 |
|---|---|
| CIDR形式 | ネットワークアドレスであること（`203.0.113.5/24` は拒否し正しい形を提示） |
| 範囲 | IPv4は `/16`、IPv6は `/32` より広いものを拒否 |
| 空の入力 | 上流が失敗して何も出さなかった場合は書き込まない |
| **件数の急減** | `replace` で30%を超えて減るなら中止 |
| IPバージョン | IPv6のリストをIPv4のIPSetに入れようとしたら中止 |
| 上限 | AWS上限の10,000件を超えるなら中止 |

急減検知に引っかかったが正当な減少だった場合:
```bash
./waf-ipset.sh replace -f list.txt --arn=$ARN --MAX_SHRINK_PERCENT=100 --apply
```

---

## 8. 設定

| 設定 | 場所 |
|---|---|
| `AWS_PROFILE_NAME` / `LOG_DIR` | `config.sh` |
| `IPSET_ARN_DEFAULT` / `MIN_PREFIX_LEN` / `MAX_SHRINK_PERCENT` など | `waf-ipset.sh` 冒頭 |
| 取得元のURL | 各取得スクリプト冒頭の `SOURCES` |

**設定項目名がそのまま引数名になる**（一時的な上書き）:
```bash
./waf-ipset.sh list --arn=$ARN --AWS_PROFILE_NAME=prod
```

EC2 で動かす場合、`AWS_PROFILE_NAME` は空のままにして
インスタンスに IAMロール（`wafv2:ListIPSets` / `GetIPSet` / `UpdateIPSet`）を付ける。
サーバ上にアクセスキーを置かずに済む。

---

## 9. エラーが出たら

aws CLI と curl の生のエラーをそのままログに出している。まずそれを読む。

| ログに出るもの | 原因 |
|---|---|
| `AccessDeniedException` | IAM権限不足 |
| `ExpiredToken` | 認証の期限切れ |
| `WAFOptimisticLockException` | 同時更新。もう一度実行すれば通る |
| `ARN の形式が正しくありません` | ARN のコピペ漏れ |
| `IPのバージョンが一致しません` | v4のリストをv6のIPSetに入れようとした |
| `HTTPステータスが 200 ではありません: 404` | 公開元がURLを変更した → `SOURCES` を直す |
| `curl の実行に失敗しました（終了コード: 6）` | DNS。cron は環境変数が違う点に注意 |
| `件数が大きく減少します` | 上流の異常か、正当な減少か確認 |

---

## 10. 対応していないもの

| 項目 | 内容 |
|---|---|
| Gemini / Copilot の個別制御 | 専用IPリストが存在しない。Gemini は Google、Copilot は Bing のIPに含まれる |
| UA別の出し分け | IPだけでは不可能。WAFルール側で文字列条件との併用が必要 |
| IPSet の作成 | 既存の IPSet を操作するだけ。作成はコンソールで行う |

---

## 動作環境

bash 4.4 以上 / `curl` / `aws` CLI v2。`jq` は不要。
Amazon Linux 2 と CentOS 7 は bash 4.2 のため動かない。

---
[zjk 2026-09-18 AI補助]
