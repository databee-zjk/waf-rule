# ip-openai.md — OpenAI（GPTBot / OAI-SearchBot / ChatGPT-User）の公式IPレンジ取得元

## 1. 結論
公式JSONあり。**取得可能**。用途別に **3ファイルに分かれている**点が重要。

## 2. 一次情報源（出典）
| 用途 | URL |
|---|---|
| 公式解説（bot一覧と使い分け） | https://platform.openai.com/docs/bots |
| GPTBot（学習用クロール） | https://openai.com/gptbot.json |
| OAI-SearchBot（ChatGPT検索のインデックス） | https://openai.com/searchbot.json |
| ChatGPT-User（ユーザ操作起因の取得） | https://openai.com/chatgpt-user.json |

### 3ファイルの意味の違い（用途判断に直結）
| UA | ファイル | 何をするか |
|---|---|---|
| `GPTBot` | gptbot.json | モデル学習用にコンテンツを収集 |
| `OAI-SearchBot` | searchbot.json | ChatGPT の検索結果に載せるためのインデックス作成 |
| `ChatGPT-User` | chatgpt-user.json | ユーザがChatGPT上でリンクを開いた等、**人間の操作起因**の取得 |

→ 「AIに学習させたくないが検索には載せたい」なら GPTBot だけ block、SearchBot は allow、という分け方になる。**3つを一緒くたに扱わないこと。**

## 3. 取得コマンド（そのまま実行可）
```bash
curl -s https://openai.com/gptbot.json
curl -s https://openai.com/searchbot.json
curl -s https://openai.com/chatgpt-user.json
```

## 4. JSON構造
```json
{
  "creationTime": "2026-09-18T00:04:57.792746",
  "prefixes": [
    { "ipv4Prefix": "104.208.184.192/28" },
    { "ipv4Prefix": "9.234.97.96/28" }
  ]
}
```
- Google / Bing と**同一形式**。パーサ共通化可。
- **IPv6 エントリは 3ファイルとも 0 件**。

## 5. 実測値（2026-09-18 時点）
| ファイル | IPv4件数 | IPv6件数 | creationTime |
|---|---|---|---|
| gptbot.json | 21 | 0 | 2025-10-30T11:00:00 |
| searchbot.json | 39 | 0 | 2026-01-02T11:00:00 |
| chatgpt-user.json | 219 | 0 | **2026-09-18T00:04:57**（当日） |
| **合計** | **279** | **0** | — |

## 6. 更新頻度・変動リスク
**3ファイルで更新頻度がまったく違う。これが本件の最重要ポイント。**
| ファイル | 最終更新 | 挙動 |
|---|---|---|
| gptbot.json | 2025-10-30 | 約11ヶ月動いていない。安定 |
| searchbot.json | 2026-01-02 | 約8ヶ月動いていない。安定 |
| chatgpt-user.json | **当日 00:04** | **毎日更新。219件と件数も多い** |

→ 「AI系のIPは変わる」という想定は **ChatGPT-User について正しい**。GPTBot/SearchBot は逆にほぼ動かない。
→ ポーリング頻度を一律にせず、chatgpt-user.json のみ高頻度で見る設計が合理的。

## 7. 注意点
- IPが Azure レンジ（`104.208.x`, `172.182.x`, `20.125.x` 等）に属する。**Azure全体を許可してはいけない**。必ずこのJSONの粒度で扱う。
- `9.234.97.96/28` のような見慣れないレンジも含まれる。手動での妥当性判断は困難 → JSONを正とする。

## 8. 自動化メモ（AWS WAF IPSet 向け）
- 全部で279件。IPSet 1つ（IPV4）に収まる。
- ただし上記の通り**用途が違うので、目的次第では3つの別IPSetに分ける**べき。block/allow を分けたい場合は必須。

---
検証: 3ファイルとも curl で実測（HTTP 200・件数・creationTime）

[zjk 2026-09-18 AI補助]
