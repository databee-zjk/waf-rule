# ip-claude.md — Anthropic Claude（ClaudeBot / Claude-User / Claude-SearchBot）の公式IPレンジ取得元

## 1. 結論
公式JSONあり。**取得可能**。ただし **UA別に分かれておらず、全クローラ合算の1ファイルのみ**。

## 2. 一次情報源（出典）
| 用途 | URL |
|---|---|
| **クローラIPレンジ JSON（これが正）** | https://claude.com/crawling/bots.json |
| 公式解説（クローラのUAと方針） | https://support.claude.com/ （"ClaudeBot" で検索） |
| （参考）API/Console の固定IP | https://platform.claude.com/docs/en/api/ip-addresses |

### 重要：混同しやすい2種類のIP
| 種別 | 意味 | 用途 |
|---|---|---|
| `claude.com/crawling/bots.json` | **Anthropicのクローラが出ていくIP** | **WAFで扱うのはこちら** |
| platform.claude.com の IP addresses | 自社→Claude API へ接続する際の**宛先/送信元**IP | WAFのクローラ制御とは無関係 |

→ 取り違えると全く効かない。**必ず bots.json を使うこと。**

## 3. 取得コマンド（そのまま実行可）
```bash
curl -s https://claude.com/crawling/bots.json
```

## 4. JSON構造
```json
{
  "creationTime": "2026-08-18T23:56:36Z",
  "prefixes": [
    { "ipv4Prefix": "216.73.216.0/22" },
    { "ipv4Prefix": "40.124.101.48/28" }
  ]
}
```
- Google / Bing / OpenAI と**同一形式**。パーサ共通化可。
- **IPv6 エントリは 0 件**。
- `creationTime` のみ **`Z` 付き ISO8601**（他社はマイクロ秒でZなし）。パース時に注意。

## 5. 実測値（2026-09-18 時点）
| 項目 | 値 |
|---|---|
| IPv4件数 | 26 |
| IPv6件数 | 0 |
| creationTime | 2026-08-18T23:56:36Z |
| レスポンスサイズ | 1,162 bytes |

## 6. 更新頻度・変動リスク
- 最終更新 2026-08-18（実測時点で約1ヶ月前）。Googleのような日次更新ではない。
- 月単位で動く印象。**日次ポーリングで十分**。

## 7. 注意点
- UA は `ClaudeBot` / `Claude-User` / `Claude-SearchBot` の3種が存在するが、**JSONはUA別に分かれていない**（OpenAIとは対照的）。
  → 「学習用だけ弾いて検索は通す」といったUA別の出し分けは、**IPだけでは不可能**。UA文字列との併用が必要。
- 旧URL `https://docs.claude.com/claudebot.json` は **301**。使わない。
- `216.73.216.0/22` など /22 の広めのレンジを含む。

## 8. 自動化メモ（AWS WAF IPSet 向け）
- 26件のみ。IPSet 1つ（IPV4）で収まる。
- UA別制御が要件にある場合、WAFルールは「IPSet一致 **AND** UA文字列一致」の複合条件になる。IPSetだけで完結しない点を設計時に織り込むこと。

---
検証: curl で実測（HTTP 200・26件・creationTime 2026-08-18Z）

[zjk 2026-09-18 AI補助]
