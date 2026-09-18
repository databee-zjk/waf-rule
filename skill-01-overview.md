# skill-01: このプロジェクトが解決している問題

> 後続 AI 向けハンドブック 1/2。もう一方は `skill-02-check.md`（定期点検）。
> 実装の詳細は `script/readme.ja.md`、情報源の根拠は `ip-*.md` を参照。

## 1. 何を解決したか

**AWS WAF の IPSet に載せる「クローラの IP 一覧」を、人手で追いかけるのをやめた。**

やりたいことは単純で、検索系クローラと AI 系クローラを WAF 側で
主体ごとに許可／拒否したい。そのためには各社が公開している IP レンジが要る。

手作業だと次の問題が出る。

| 問題 | 実際に起きること |
|---|---|
| 公開元が更新される | Google は日次で変わる。追随しないと正当な Googlebot を弾く |
| 公開 URL 自体が変わる | Google は 2026-03 に配布 URL を実際に移転した |
| 主体ごとに公開形式が違う | 1 本の JSON で済む所（Bing）と 5 本に分かれている所（Google）がある |
| 件数が正しいか判断できない | 「本来何件あるべきか」は取得側には分からない |

この 4 つを、取得スクリプト群と `waf-ipset.sh` の組み合わせで自動化した。

## 2. 対象の 6 主体

| 主体 | 分類 | 専用 IP リスト | 手掛かり |
|---|---|---|---|
| Google Bot | 検索 | あり（5 本） | `ip-google-bot.md` |
| Bing Bot | 検索 | あり（1 本） | `ip-bing-bot.md` |
| OpenAI | AI | あり（3 本 = 用途別） | `ip-openai.md` |
| Claude | AI | あり | `ip-claude.md` |
| Gemini | AI | **なし**（Google の IP に内包） | `ip-gemini.md` |
| Copilot | AI | **なし**（Bing の IP に内包） | `ip-copilot.md` |

Gemini と Copilot は専用リストが存在しないため、IP による制御の対象外。
制御が要る場合は robots.txt を使う。取得スクリプトが 4 本しかないのはこのため。

## 3. 全体の構成

**取得スクリプトが標準出力に CIDR を吐き、`waf-ipset.sh` が受け取って書き込む。**
間はパイプでつなぐだけ。

```
<取得スクリプト> | waf-ipset.sh replace -f - --IPSET_NAME=<名前> --apply
```

```bash
./get-google-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=google-list --apply
./get-bing-ip.sh   | ./waf-ipset.sh replace -f - --IPSET_NAME=bing-list   --apply
./get-openai-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=openai-list --apply
./get-claude-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=claude-list --apply
```

| ファイル | 役割 | AWS 接続 |
|---|---|---|
| `script/get-*-ip.sh` | 各主体の IP 取得。**URL 表を自分で持つ** | しない |
| `script/lib/crawler-ip.lib.sh` | 取得の手順（HTTP・JSON 解析・検証）。**URL は持たない** | しない |
| `script/config.sh` | 共通設定（AWS 接続先）と共通関数 | しない |
| `script/waf-ipset.sh` | IPSet の表示・追加・削除・置換 | する |

## 4. 設計上、意図してそうしてある点

後続 AI が「整理した方がよい」と誤って直しやすい箇所。**理由があってこうなっている。**

### URL を lib に集約していない

公開 URL はその主体固有の資産なので、各取得スクリプトが持つ。
**URL が変わったら、その主体の 1 ファイルだけ直せば済む。**
共通化すると 1 主体の変更が全主体に影響する。

### IPSet を主体ごとに分けている

まとめると**主体ごとに別方針を取れなくなる**。
特に OpenAI は用途別に 3 本公開しているので、分けておけば
「学習（GPTBot）は拒否、AI 検索（OAI-SearchBot）は許可」が選べる。

### 取得側は件数の多寡を判定しない

取得スクリプトは「**取れた / 取れない**」しか見ない。期待値を持たない。

- 公開元が正当に増減しただけで誤検知する
- 「本来何件あるべきか」はこちらには分からない。公開元の件数が正
- 「取れたが異常に少ない」の防護は `waf-ipset.sh` 側の `MAX_SHRINK_PERCENT`
  （現 IPSet との相対比較なので、期待値を書かなくてよい）

0 件のみ「取れなかった」として失敗させる
（IPv6 を公開していない取得源があるため、IPv6 の 0 件は正常）。

### 取得失敗時に 0 件を出力せず異常終了する

0 件を流すと `waf-ipset.sh` が IPSet を空にしてしまう。
**取得スクリプトの契約は「正しい一覧を出す、出せないなら落ちる」。**

## 5. 安全装置

`waf-ipset.sh` は上流が何であれ、書き込み前に必ず検査する。

| 検査 | 内容 |
|---|---|
| CIDR 形式 | 形式・範囲・**ネットワークアドレスであること** |
| 広すぎる指定 | `MIN_PREFIX_LEN`（既定 /16）より広いものを拒否 |
| 空入力 | 上流が失敗して何も出力しなかった場合、書き込まず中止 |
| 件数の急減 | `replace` 時、`MAX_SHRINK_PERCENT`（既定 30%）超の減少で中止 |
| 件数上限 | AWS 上限 10,000 件超で中止 |
| 既定はドライラン | `--apply` がなければ書き込まない |

正当な減少と確認できたら `--MAX_SHRINK_PERCENT=100` を付けて再実行する。

## 6. コスト

**このスクリプト群の実行費用は $0。**
各社の公開エンドポイントへの HTTPS GET は無料・認証不要、
WAF の `list-ip-sets` / `get-ip-set` / `update-ip-set` はいずれも課金対象外。
毎時実行しても増えない。実際は日次 1 回で足りる。

## 7. 未対応

| 項目 | 状況 |
|---|---|
| IPv6 | 取得は `--ipv6` で可能だが、`waf-ipset.sh` が IPv4 のみのため反映できない |
| UA 別の区別 | IP だけでは不可能。WAF ルール側で文字列条件の併用が要る |
| Gemini / Copilot | 専用 IP リストが無いため対象外（§2 参照） |

## 8. 検証状況

構文・入力検証・正常系・冪等性・設定上書き・急減検知・実通信での取得
（google 182 / bing 28 / openai 39 / claude 26 件）・HTTP 異常・AWS 権限異常は確認済み。

**未検証: 実 AWS 環境への書き込み。** AWS 接続は一度も行っていない。
本番適用前に、影響のないテスト用 IPSet で `--apply` を 1 回実行して確認すること。

---
[zjk 2026-09-18 AI補助]
