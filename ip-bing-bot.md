# ip-bing-bot.md — Bingbot（検索系クローラ）の公式IPレンジ取得元

## 1. 結論
公式JSONあり。**取得可能**。ただし **2024-01-03 以降 2年半以上更新されていない**（後述）。

## 2. 一次情報源（出典）
| 用途 | URL |
|---|---|
| JSON本体 | https://www.bing.com/toolbox/bingbot.json |
| 公式アナウンス（Bing Blogs） | https://blogs.bing.com/webmaster/ （"bingbot IP ranges" で検索） |
| 逆引き検証の公式手順 | https://www.bing.com/webmasters/help/how-to-verify-bingbot-3905dc26 |

## 3. 取得コマンド（そのまま実行可）
```bash
curl -s https://www.bing.com/toolbox/bingbot.json
```

## 4. JSON構造
```json
{
  "creationTime": "2024-01-03T10:00:00.121331",
  "prefixes": [
    { "ipv4Prefix": "157.55.39.0/24" },
    { "ipv4Prefix": "40.77.188.0/22" }
  ]
}
```
- Google / OpenAI と**同じ形式**（`creationTime` + `prefixes`）。パーサは共通化できる。
- **IPv6 エントリは 0 件**。`ipv4Prefix` のみ。

## 5. 実測値（2026-09-18 時点）
| 項目 | 値 |
|---|---|
| IPv4件数 | 28 |
| IPv6件数 | 0 |
| creationTime | 2024-01-03T10:00:00.121331 |
| レスポンスサイズ | 1,580 bytes |

## 6. 更新頻度・変動リスク
- **実質的に更新されていない**。`creationTime` は 2024-01-03 のまま（2026-09-18 時点で約2年8ヶ月経過）。
- Google が毎日更新なのと対照的。**「変動が小さい」のではなく「メンテされているか不明」と捉えるべき**。
- リスク：Microsoft が新レンジを追加してもこのJSONに反映されない可能性がある。
  → allow 用途で使う場合、このリストにない正規 Bingbot を弾く事故があり得る。
  → 補助手段として逆引き（`*.search.msn.com`）検証を併用する設計が安全。

## 7. 注意点
- User-Agent は `bingbot`（検索）と `BingPreview`（プレビュー）等が存在するが、JSONはUA別に分かれていない。**1ファイルのみ**。
- このIPレンジは Bing 検索だけでなく **Microsoft Copilot / Yahoo / DuckDuckGo** のクロールも担う（→ ip-copilot.md 参照）。

## 8. 自動化メモ（AWS WAF IPSet 向け）
- 28件のみ。IPSet 1つ（IPV4）で収まる。
- 変動しないため、毎時ポーリングはほぼ無意味。**日次で十分**。ただし取得コスト自体が $0 なので毎時でも害はない。

---
検証: curl で実測（HTTP 200・28件・creationTime 2024-01-03）

[zjk 2026-09-18 AI補助]
