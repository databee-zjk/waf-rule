# ip-gemini.md — Google Gemini の IPレンジ取得元

## 1. 結論
**Gemini 専用の公式IPリストは存在しない。**
Gemini のクロールは Google 共通のクローラ基盤から出るため、**ip-google-bot.md のJSONに含まれる**。
→ 「Geminiだけを IP で識別する」ことは**できない**。

## 2. 根拠（出典）
| 内容 | URL |
|---|---|
| Google公式：クローラ検証（Gemini専用ファイルの記載なし） | https://developers.google.com/crawling/docs/crawlers-fetchers/verify-google-requests |
| URL移転告知：「Shopping・AdSense・**Gemini** 等でも使われるため /search/ から /crawling/ に移す」 | https://developers.google.com/search/blog/2026/03/crawler-ip-ranges |
| Google公式：Google-Extended の説明（robots.txt トークンであり、独立したクローラではない） | https://developers.google.com/search/docs/crawling-indexing/overview-google-crawlers |

→ 2026-03 の移転告知そのものが「**既存のクローラIPレンジが Gemini もカバーしている**」ことの公式な裏付けになっている。

## 3. 取得コマンド
Gemini専用エンドポイントは無いため、ip-google-bot.md と同じものを使う：
```bash
curl -s https://developers.google.com/static/crawling/ipranges/common-crawlers.json
curl -s https://developers.google.com/static/crawling/ipranges/user-triggered-agents.json
```

## 4. Gemini の制御は「IP」ではなく「User-Agent / robots.txt」で行う
| トークン | 意味 |
|---|---|
| `Google-Extended` | Gemini のモデル学習・グラウンディングへの利用可否を robots.txt で制御するトークン。**独立したUA/クローラではない**（Googlebot がクロールし、このトークンで利用可否を判定） |
| `Google-CloudVertexBot` | Vertex AI 用の取得。要確認 |

→ **Gemini を止めたいなら robots.txt の `User-agent: Google-Extended` / `Disallow: /`** が公式の手段。
→ WAFのIP制御でGeminiだけを止めようとすると、**Googlebot（検索インデックス）も巻き込んで検索流入を失う**。これは事故になる。

## 5. 未確認事項（要調査）
- `user-triggered-agents.json`（IPv4 12件 / IPv6 8件）が**どのUAをカバーするか、公式に明記がない**。
  Gemini のエージェント的な取得（Deep Research 等）がここに該当する可能性があるが、**裏が取れていない**。
  → 断定せず、必要になった時点で Google のドキュメント更新を再確認すること。

## 6. 実測値（2026-09-18 時点）
Gemini専用の数値は存在しない。ip-google-bot.md の表を参照。

## 7. 自動化メモ（AWS WAF IPSet 向け）
- **Gemini 用の独立した IPSet は作らない**（作れない）。
- 要件が「Geminiの学習利用を拒否」なら、**WAFではなく robots.txt が正しい実装場所**。
- 要件が「Google系クローラを許可」なら ip-google-bot.md の IPSet に含まれるので、追加作業は不要。

### 許可（allow）目的の場合のカバー範囲
「IPで識別できない」ことは、**許可目的では不利にならない**。Google を許可すれば Gemini も許可されるため。
ただし取りこぼしを避けるなら、投入ファイルは `common-crawlers` のみでは不足の可能性がある。

| ファイル | 許可目的での要否 | 理由 |
|---|---|---|
| `common-crawlers` | **必須**（IPv4 170 / IPv6 147） | Googlebot 本体。Gemini の grounding クロールもここ |
| `user-triggered-agents` | **推奨**（IPv4 12 / IPv6 8） | Gemini の Deep Research 等が該当する可能性（5章の未確認事項）。件数が極小のため、入れておくコストがほぼゼロ |
| `special-crawlers` / `user-triggered-fetchers*` | 任意 | AdsBot・サイト所有権確認等。Gemini とは無関係 |

→ 許可目的の推奨構成は **`common-crawlers` + `user-triggered-agents`**（IPv4 182件 / IPv6 155件）。

---
検証: Google公式ドキュメント2件＋移転告知で確認。専用エンドポイントの不在を確認済み

[zjk 2026-09-18 AI補助]
