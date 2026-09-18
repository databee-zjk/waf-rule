# 実環境テスト用コマンド集

**1行ずつコピペして使う。** どの行も単独で動く（事前の設定は不要）。
Git Bash 前提。

> ⚠ このファイルには実環境の ARN（アカウントID含む）が入っている。
> リポジトリに含めたくない場合は `.gitignore` に `test.md` を追加すること。

最初にディレクトリだけ移動しておく:

```bash
cd /c/Users/chou_ketukon/Documents/ev.miraie/src/framework/script/waf-rule/script
```

### 対象の ARN（コピペ元）

| 名前 | ARN |
|---|---|
| CloudFront v4 | `arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv4/a353060a-9ca7-441e-9600-54640f46a887` |
| CloudFront v6 | `arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1` |
| ALB v4 | `arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8` |
| ALB v6 | `arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv6/8b2b745f-82c3-4ac1-bd9a-7bcf66650191` |

---

# ■ 通し試験（まずこれをやる）

**空 → 書き込み → 確認 → 空** を一周する。上から順に1行ずつ実行する。

2パターンやることで、4つの組み合わせのうち対角の2つを確認できる。

| | スコープ | IPバージョン | 使う取得元 |
|---|---|---|---|
| パターンA | REGIONAL（ALB） | IPv4 | Bing（28件・安定） |
| パターンB | CLOUDFRONT（global） | IPv6 | Google（147件） |

---

## パターンA: ALB（リージョン） × IPv4

### A-1. 現在の内容を見る

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

→ 対象名・スコープ・リージョンが表示されればOK

### A-2. いったん空にする

```bash
./waf-ipset.sh clear --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply
```

→ 終了コード0（空にした）か 3（元々空）ならOK

### A-3. 空になったことを確認

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

→ `登録件数: 0 件` ならOK

### A-4. Bing のIPを書き込む

```bash
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply
```

→ `件数: 0 件 → 28 件` と出て `*** 書き込みました。 ***` ならOK

### A-5. 入ったことを確認

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

→ `登録件数: 28 件` と一覧が出ればOK

### A-6. 取得元と1件単位で一致するか照合

```bash
./get-bing-ip.sh 2>/dev/null | sort > expect-a.txt && ./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --pipe 2>/dev/null | sort > actual-a.txt && diff expect-a.txt actual-a.txt && echo "★ パターンA 完全一致"
```

→ `★ パターンA 完全一致` が出ればOK（差分があれば diff が表示される）

### A-7. もう一度同じことをして、書き込まないことを確認

```bash
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply ; echo "終了コード=$?（3なら正常）"
```

→ `変更はありません` ＋ 終了コード3 ならOK

### A-8. 空に戻す

```bash
./waf-ipset.sh clear --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply
```

### A-9. 空になったことを確認

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

→ `登録件数: 0 件` ならパターンA完了

---

## パターンB: CloudFront（グローバル） × IPv6

### B-1. 現在の内容を見る

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1
```

→ `CLOUDFRONT / us-east-1` と表示されればOK（リージョンがARNから自動判別されている）

### B-2. いったん空にする

```bash
./waf-ipset.sh clear --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1 --apply
```

### B-3. 空になったことを確認

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1
```

### B-4. Google の IPv6 を書き込む

```bash
./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1 --apply
```

→ `件数: 0 件 → 147 件` 程度（Google側の更新で変動する）

### B-5. 入ったことを確認

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1
```

### B-6. 取得元と1件単位で一致するか照合

```bash
./get-google-ip.sh --ipv6 2>/dev/null | sort > expect-b.txt && ./waf-ipset.sh list --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1 --pipe 2>/dev/null | sort > actual-b.txt && diff expect-b.txt actual-b.txt && echo "★ パターンB 完全一致"
```

→ `★ パターンB 完全一致` が出ればOK

### B-7. もう一度同じことをして、書き込まないことを確認

```bash
./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1 --apply ; echo "終了コード=$?（3なら正常）"
```

### B-8. 空に戻す

```bash
./waf-ipset.sh clear --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1 --apply
```

### B-9. 空になったことを確認

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1
```

→ `登録件数: 0 件` ならパターンB完了

### 後片付け

```bash
rm -f expect-a.txt actual-a.txt expect-b.txt actual-b.txt
```

---

## 通し試験で確認できること

| 確認できること | どの手順で |
|---|---|
| 接続・権限・ARN解析 | A-1 / B-1 |
| リージョンとスコープの自動判別 | B-1（us-east-1 / CLOUDFRONT と出る） |
| 全件削除 | A-2 / A-8 |
| 取得から反映までの一連 | A-4 / B-4 |
| **書き込み内容が取得内容と完全一致すること** | **A-6 / B-6** |
| 冪等性（2回目は書き込まない） | A-7 / B-7 |
| IPv4 と IPv6 の両対応 | A と B |
| REGIONAL と CLOUDFRONT の両対応 | A と B |

**A-6 と B-6 が通れば、本番適用の判断材料としては十分。**

---

# ■ 個別のコマンド

## 1. まず現状を保存（テスト後に戻せるようにする）

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --pipe > backup-alb-v4.txt
```

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv4/a353060a-9ca7-441e-9600-54640f46a887 --pipe > backup-cf-v4.txt
```

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv6/8b2b745f-82c3-4ac1-bd9a-7bcf66650191 --pipe > backup-alb-v6.txt
```

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1 --pipe > backup-cf-v6.txt
```

```bash
wc -l backup-*.txt
```

---

## 2. 読み取りだけ（何も変更しない）

接続・権限・ARN が正しいかの確認。**ここが通れば設定は正しい。**

ALB v4:
```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

CloudFront v4:
```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv4/a353060a-9ca7-441e-9600-54640f46a887
```

ALB v6:
```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv6/8b2b745f-82c3-4ac1-bd9a-7bcf66650191
```

CloudFront v6:
```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1
```

4つとも `対象: 名前（スコープ / リージョン）` が出て一覧が表示されればOK。

---

## 3. 取得だけ（AWSに触らない）

```bash
./get-bing-ip.sh
```

```bash
./get-google-ip.sh
```

```bash
./get-google-ip.sh --ipv6
```

```bash
./get-openai-ip.sh
```

```bash
./get-claude-ip.sh
```

---

## 4. 模擬実行（差分は出るが、書き込まない）

`--apply` が無いので安全。**何が起きるかだけ確認できる。**

Bing → ALB v4:
```bash
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

Google → ALB v4:
```bash
./get-google-ip.sh | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

Google IPv6 → ALB v6:
```bash
./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv6/8b2b745f-82c3-4ac1-bd9a-7bcf66650191
```

---

## 5. 実際に書き込む

**Bing から始めるのを推奨**（28件と少なく、2年以上内容が変わっていないため照合しやすい）。

Bing → ALB v4:
```bash
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply
```

Bing → CloudFront v4:
```bash
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv4/a353060a-9ca7-441e-9600-54640f46a887 --apply
```

Google IPv6 → ALB v6:
```bash
./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv6/8b2b745f-82c3-4ac1-bd9a-7bcf66650191 --apply
```

Google IPv6 → CloudFront v6:
```bash
./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1 --apply
```

---

## 6. 書き込み結果の照合（これが本番の判断材料）

**書き込んだ内容と、AWSに入った内容が1件単位で一致するか。**

期待値を作る:
```bash
./get-bing-ip.sh 2>/dev/null | sort > expect.txt
```

実際に入っている内容を取る:
```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --pipe 2>/dev/null | sort > actual.txt
```

比べる（差分ゼロなら成功）:
```bash
diff expect.txt actual.txt && echo "★ 完全一致"
```

IPv6版:
```bash
./get-google-ip.sh --ipv6 2>/dev/null | sort > expect6.txt
```

```bash
./waf-ipset.sh list --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv6/8b2b745f-82c3-4ac1-bd9a-7bcf66650191 --pipe 2>/dev/null | sort > actual6.txt
```

```bash
diff expect6.txt actual6.txt && echo "★ 完全一致"
```

---

## 7. 冪等性の確認（2回目は書き込まないこと）

手順5と同じコマンドをもう一度流す。**「変更はありません」＋終了コード3 が出れば正しい。**

```bash
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply ; echo "終了コード=$?（3なら正常）"
```

---

## 8. 単発操作（手で1件だけ足す・消す）

模擬:
```bash
./waf-ipset.sh add 203.0.113.0/24 --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

追加:
```bash
./waf-ipset.sh add 203.0.113.0/24 --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply
```

削除:
```bash
./waf-ipset.sh del 203.0.113.0/24 --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply
```

IPv6を追加:
```bash
./waf-ipset.sh add 2001:db8:1234::/48 --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv6/8b2b745f-82c3-4ac1-bd9a-7bcf66650191 --apply
```

IPv6を削除:
```bash
./waf-ipset.sh del 2001:db8:1234::/48 --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv6/8b2b745f-82c3-4ac1-bd9a-7bcf66650191 --apply
```

---

## 9. 安全装置の確認（**全部エラーになれば正常**）

ネットワークアドレスでない → 拒否されるはず:
```bash
./waf-ipset.sh add 203.0.113.5/24 --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

範囲が広すぎる → 拒否されるはず:
```bash
./waf-ipset.sh add 10.0.0.0/8 --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

空の入力 → 拒否されるはず:
```bash
./waf-ipset.sh replace -f /dev/null --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

IPv6 を IPv4 の IPSet へ → 拒否されるはず:
```bash
./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8
```

IPSet以外のARN → 拒否されるはず:
```bash
./waf-ipset.sh list --arn=arn:aws:s3:::bucket
```

対象未指定 → 案内が出るはず:
```bash
./waf-ipset.sh list
```

急減検知（2件に減らそうとして止まるか）:
```bash
printf '%s\n' 192.0.2.0/24 198.51.100.0/24 > tiny.txt
```

```bash
./waf-ipset.sh replace -f tiny.txt --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply ; echo "終了コード=$?（1なら正常：急減を検知）"
```

止まったものを意図的に通す:
```bash
./waf-ipset.sh replace -f tiny.txt --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --MAX_SHRINK_PERCENT=100 --apply
```

---

## 10. 元に戻す（テスト終了後）

手順1のバックアップから復元する。
件数が減る方向なので `--MAX_SHRINK_PERCENT=100` を付ける。

ALB v4:
```bash
./waf-ipset.sh replace -f backup-alb-v4.txt --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --MAX_SHRINK_PERCENT=100 --apply
```

CloudFront v4:
```bash
./waf-ipset.sh replace -f backup-cf-v4.txt --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv4/a353060a-9ca7-441e-9600-54640f46a887 --MAX_SHRINK_PERCENT=100 --apply
```

ALB v6:
```bash
./waf-ipset.sh replace -f backup-alb-v6.txt --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv6/8b2b745f-82c3-4ac1-bd9a-7bcf66650191 --MAX_SHRINK_PERCENT=100 --apply
```

CloudFront v6:
```bash
./waf-ipset.sh replace -f backup-cf-v6.txt --arn=arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1 --MAX_SHRINK_PERCENT=100 --apply
```

バックアップが0件だった場合は `replace` できない（空入力は拒否されるため）。
その場合はコンソールから手で空にする。

一時ファイルの掃除:
```bash
rm -f expect.txt actual.txt expect6.txt actual6.txt tiny.txt
```

---

## 11. crontab に載せる形での確認

実際に cron で動く形と同じ（`--pipe` 付き、ログへリダイレクト）。

```bash
./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8 --apply --pipe >> /tmp/waf-test.log 2>&1 ; echo "終了コード=$?"
```

```bash
tail -20 /tmp/waf-test.log
```

```bash
grep ERROR /tmp/waf-test.log
```

---

## 困ったとき

| 症状 | 確認すること |
|---|---|
| `AccessDeniedException` | IAM権限（`ListIPSets` / `GetIPSet` / `UpdateIPSet`） |
| `ExpiredToken` | `aws sso login` 等で認証を取り直す |
| `WAFOptimisticLockException` | 誰かが同時に更新した。もう一度実行すれば通る |
| `ARN の形式が正しくありません` | ARN のコピペ漏れ。前後の空白や改行に注意 |
| `IPのバージョンが一致しません` | v4のリストをv6のIPSetに入れようとしている |
| コマンドが固まる | `--pipe` を付けるか、頭に `NO_PAUSE=1 ` を付ける |

生の aws エラーはそのままログに出るので、まずそれを読む。

---
[zjk 2026-09-18 AI補助]
