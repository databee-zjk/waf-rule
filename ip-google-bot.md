# ip-google-bot.md — Googlebot（検索系クローラ）の公式IPレンジ取得元

## 1. 結論
公式JSONあり。**取得可能**。ただし 2026-03-31 にURLが移転済み（旧URLは 301）。

## 2. 一次情報源（出典）
| 用途 | URL | 備考 |
|---|---|---|
| 検証手順の公式解説 | https://developers.google.com/crawling/docs/crawlers-fetchers/verify-google-requests | ここが正の出典 |
| URL移転の告知 | https://developers.google.com/search/blog/2026/03/crawler-ip-ranges | 2026-03-31 告知 |

### JSONファイル（5種）
| ファイル | URL | 中身 |
|---|---|---|
| common-crawlers | https://developers.google.com/static/crawling/ipranges/common-crawlers.json | **Googlebot 本体**。robots.txt に従う通常クローラ |
| special-crawlers | https://developers.google.com/static/crawling/ipranges/special-crawlers.json | AdsBot 等、特定機能用 |
| user-triggered-fetchers | https://developers.google.com/static/crawling/ipranges/user-triggered-fetchers.json | ユーザ操作起因の取得（`gae.googleusercontent.com` 系） |
| user-triggered-fetchers-google | https://developers.google.com/static/crawling/ipranges/user-triggered-fetchers-google.json | 同上（`google.com` 系） |
| user-triggered-agents | https://developers.google.com/static/crawling/ipranges/user-triggered-agents.json | **どのUAを含むか公式に明記なし（未確認）**。AI系エージェントの可能性あり、要調査 |

参考：https://www.gstatic.com/ipranges/goog.json は Google 全体のIP（クローラに限らない）。**WAFのallow用途には広すぎる。使わない。**

## 3. 取得コマンド（そのまま実行可）
```bash
curl -s https://developers.google.com/static/crawling/ipranges/common-crawlers.json
```

## 4. JSON構造
```json
{
  "creationTime": "2026-09-17T14:46:07.000000",
  "prefixes": [
    { "ipv4Prefix": "192.178.5.0/27" },
    { "ipv6Prefix": "2001:4860:4801:10::/64" }
  ]
}
```
- `prefixes` は配列。要素は `ipv4Prefix` **または** `ipv6Prefix` のどちらか一方のキーを持つ。
- パース時に両方を想定すること（Googleのみ IPv6 を大量に含む）。

## 5. 実測値（2026-09-18 時点）
| ファイル | IPv4件数 | IPv6件数 | creationTime |
|---|---|---|---|
| common-crawlers | 170 | 147 | 2026-09-17T14:46:07 |
| special-crawlers | 136 | 136 | 2026-09-17T14:46:05 |
| user-triggered-fetchers | 529 | 529 | 2026-09-17T14:46:04 |
| user-triggered-fetchers-google | 248 | 248 | 2026-09-17T14:46:03 |
| user-triggered-agents | 12 | 8 | 2026-09-17T14:46:07 |
| **合計** | **1,095** | **1,068** | — |

## 6. 更新頻度・変動リスク
- `creationTime` が**毎日更新**される（実測：前日付）。変動は大きい方。
- 中身が変わらなくても `creationTime` は動く可能性があるため、**差分判定は creationTime ではなく prefixes の集合比較で行うこと**。

## 7. 注意点
- 旧URL `https://developers.google.com/static/search/apis/ipranges/googlebot.json` は **301**。追従せず新URLを直接叩く。
- 旧 `googlebot.json` → 新 `common-crawlers.json` に**名前も変わっている**（単純なパス置換では当たらない）。
- `www.gstatic.com/crawling/ipranges/...` は **404**。gstatic 配下にクローラ用JSONは存在しない。

## 8. 自動化メモ（AWS WAF IPSet 向け）
- IPSet は IPv4 と IPv6 を**同居できない**（`CreateIPSet` の `IPAddressVersion` は IPV4 / IPV6 の排他指定）。→ Google系は最低2セット必要。
- 全5ファイルを入れると IPv4 1,095 件。IPSet 上限 10,000 件には余裕あり。
- ただし用途が「検索クローラの許可」だけなら **common-crawlers のみ**で足りる（170件）。user-triggered-fetchers* はユーザ操作起因であり、クローラ許可の意図とは別物。
- **ただし許可対象に Gemini を含めたい場合は `user-triggered-agents` も追加する**（IPv4 12件 / IPv6 8件）。Gemini の Deep Research 等がここに該当する可能性があり（ip-gemini.md 5章の未確認事項）、件数が極小のため入れておくコストがほぼゼロ。→ 推奨構成は **common-crawlers + user-triggered-agents**（IPv4 182件 / IPv6 155件）。

---
検証: 全URLを curl で実測（HTTPステータス・件数・creationTime）

[zjk 2026-09-18 AI補助]
