# ip-copilot.md — Microsoft Copilot の IPレンジ取得元

## 1. 結論
**Copilot 専用の公式IPリストは存在しない。**
Copilot のWebコンテンツ取得は Bingbot の基盤を共有するため、**ip-bing-bot.md のJSONに含まれる**。
→ 「Copilotだけを IP で識別する」ことは**できない**。

## 2. 根拠（出典）
| 内容 | URL |
|---|---|
| Bingbot の JSON（Copilot もこの基盤を使う） | https://www.bing.com/toolbox/bingbot.json |
| Microsoft公式：Bingbot の検証方法 | https://www.bing.com/webmasters/help/how-to-verify-bingbot-3905dc26 |
| Microsoft公式：クロール制御 / Bing Webmaster Tools | https://www.bing.com/webmasters/ |

→ Bingbot が Bing検索・**Copilot**・Yahoo・DuckDuckGo 向けのクロールを兼ねている。Copilot専用エンドポイントは公開されていない。

## 3. 取得コマンド
Copilot専用エンドポイントは無いため、ip-bing-bot.md と同じものを使う：
```bash
curl -s https://www.bing.com/toolbox/bingbot.json
```

## 4. 注意点（GitHub Copilot とは別物）
「Copilot」は Microsoft 製品名として複数存在する。**混同しないこと。**
| 名称 | 何か | 本件との関係 |
|---|---|---|
| Microsoft Copilot（旧 Bing Chat） | Web検索連動のAIアシスタント | **本ファイルの対象**。Bingbot 基盤 |
| GitHub Copilot | コード補完。ユーザのリポジトリを扱う | Webクロールとは無関係。**対象外** |
| Microsoft 365 Copilot | 社内文書向け | 公開Webのクロールとは無関係。**対象外** |

## 5. 未確認事項（要調査）
- Copilot の「ユーザ操作起因の取得」（ユーザがCopilotにURLを渡して読ませる等）が Bingbot と同じIPから出るのか、別経路なのかは**公式に明記がない**。
  OpenAI が `ChatGPT-User` を別ファイルにしているのと対照的に、Microsoft は分離していない。
  → 実トラフィックのログでUA `bingbot` 以外のMicrosoft系UAが観測されたら、その時点で再調査。

## 6. 実測値（2026-09-18 時点）
Copilot専用の数値は存在しない。ip-bing-bot.md（IPv4 28件 / creationTime 2024-01-03）を参照。

## 7. 自動化メモ（AWS WAF IPSet 向け）
- **Copilot 用の独立した IPSet は作らない**（作れない）。
- 要件が「Copilotだけ止めたい」場合、IPでは不可能。**Bingbot を止めると Bing検索のインデックスも失う**ため、WAFでのIP制御は手段として適さない。
  → robots.txt で該当トークンを Disallow するのが正しい実装場所。
- 要件が「検索クローラを許可」なら ip-bing-bot.md の IPSet に含まれるので追加作業は不要。

### 許可（allow）目的の場合のカバー範囲
「IPで識別できない」ことは、**許可目的では不利にならない**。Bingbot を許可すれば Copilot も許可されるため、Copilot 用の作業は発生しない。
ただし次の2点を前提として明示しておくこと。

| 前提 | 内容 |
|---|---|
| カバー率は Bingbot リストの鮮度に依存 | `bingbot.json` は `creationTime` が 2024-01-03 のまま（ip-bing-bot.md 参照）。Microsoft が新IPを使い始めていれば、**Copilot の通信も同じだけ取りこぼす**。対策は Bingbot と同一（逆引きDNS `*.search.msn.com` の併用） |
| カバーされるのは Microsoft Copilot のみ | GitHub Copilot / Microsoft 365 Copilot は Bingbot 基盤を使わないため対象外（4章）。ただし公開Webのクロールを行わないため、許可リストに入れる必要もない |

---
検証: Bingbot JSONの実測＋Copilot専用エンドポイントの不在を確認

[zjk 2026-09-18 AI補助]
