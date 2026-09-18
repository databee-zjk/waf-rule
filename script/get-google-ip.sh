#!/usr/bin/env bash
#
# ============================================================================
# get-google-ip.sh — Google が公開しているクローラIPを取得する
# ============================================================================
#
# 【用途】
#   Google公式の ipranges JSON から IPレンジを取得し、CIDR を1行1件で出力する。
#   waf-ipset.sh にパイプでそのまま渡せる形式。
#
# 【Gemini について】
#   Gemini 専用のIPリストは存在しない。Google共通のクローラ基盤から通信するため、
#   本スクリプトの出力に含まれる。「Geminiだけ許可／遮断」はIPでは実現できない。
#   詳細は ../ip-gemini.md を参照。
#
# 【既定の構成をこうしている理由】
#   Google は用途の異なる5ファイルを公開している。全部入れる必要はない。
#   既定は「許可リスト用」を想定し、以下の2つにしてある。
#     google-crawler  Googlebot 本体。検索インデックスのクロール
#     google-agents   用途はGoogle未公表。Gemini の Deep Research 等が
#                     該当する可能性がある（裏は取れていない）。
#                     IPv4 12件と極小のため、取りこぼしを避けて入れてある
#   広告配信（AdsBot）やサイト所有権確認まで許可したい場合は --all を使う。
#
# 【用法（最もよく使う形）】
#   ./get-google-ip.sh                       既定の構成で取得（IPv4）
#   ./get-google-ip.sh --ipv6                既定の構成の IPv6
#   ./get-google-ip.sh --all                 公開5ファイル全部
#   ./get-google-ip.sh --only google-crawler Googlebot 本体だけ
#   ./get-google-ip.sh --list                取得元の一覧を表示
#   ./get-google-ip.sh > google.txt          ファイルに保存
#
# 【入参】
#   オプションのみ。詳細は --help を参照。
#
# 【出参】
#   標準出力: CIDR を1行1件（これ以外は出力しない。パイプで繋げる）
#   標準エラー: 進捗と警告
#   終了コード: 0=成功 / 2=引数エラー / 1=取得失敗・健全性チェック不合格
#
# 【Enter待ちをしない理由（claude.md 第5条からの意図的な逸脱）】
#   本スクリプトは標準出力にCIDRだけを出すデータ供給役のため、終了時のEnter待ちをしない。
#   パイプ・リダイレクト・上位スクリプトからの呼び出しが前提で、待つと処理が止まるため。
#   書き込みを伴う waf-ipset.sh は規約どおりEnter待ちをする。
#
# 【実行環境】
#   Git Bash（Windows）/ bash 4.4 以上。curl が必要。jq は不要。
#
# 【費用】
#   Google の公開エンドポイントへの HTTPS GET のみ。$0。
#   認証不要・レート制限の明示なし。1日数回程度の取得で問題になることはない。
#
# [zjk 2026-09-18 AI補助]
# ============================================================================

set -u

# ---- 本スクリプトの設定（改这里）------------------------------------------

# 表示用の名前。
NODE_NAME="Google"

# オプション無しの時に取得する取得元。空白区切り。
# 変更すると既定の出力内容が変わる。理由は上の【既定の構成をこうしている理由】参照。
NODE_DEFAULT="google-crawler google-agents"

# --all の時に取得する取得元。Google が公開している全5ファイル。
NODE_ALL="google-crawler google-special google-fetchers google-fetchers-google google-agents"

# 取得元の定義。取得元1つにつき url / desc の2項目。
#   url  … 公開JSONのURL
#   desc … ログに出す説明
#
# URLの注意:
#   Google は 2026-03-31 に公開場所を /search/apis/ipranges/ から /crawling/ipranges/ へ
#   移転し、さらに googlebot.json を common-crawlers.json へ改名した。旧URLは301を返す。
#   今後も変わりうるので、301や404で失敗したら ../ip-google-bot.md の出典を確認して
#   ここを直す。直す場所はこのファイルだけ。
#
# 括弧内の実測件数は規模の目安であり、判定には使っていない。
# 取得できたかどうかだけを見て、件数はGoogleが出したものを正とする。

declare -A SOURCES=(
    # --- Googlebot 本体。検索インデックスのクロール（2026-09-18 実測 170件）---
    [google-crawler.url]="https://developers.google.com/static/crawling/ipranges/common-crawlers.json"
    [google-crawler.desc]="Googlebot 本体（検索クローラ）"

    # --- AdsBot 等。広告配信の確認用（2026-09-18 実測 136件）---
    [google-special.url]="https://developers.google.com/static/crawling/ipranges/special-crawlers.json"
    [google-special.desc]="AdsBot 等の特定機能用"

    # --- ユーザ操作起因の取得（gae.googleusercontent.com 系。実測 529件）---
    [google-fetchers.url]="https://developers.google.com/static/crawling/ipranges/user-triggered-fetchers.json"
    [google-fetchers.desc]="ユーザ操作起因の取得（gae系）"

    # --- ユーザ操作起因の取得（google.com 系。実測 248件）---
    [google-fetchers-google.url]="https://developers.google.com/static/crawling/ipranges/user-triggered-fetchers-google.json"
    [google-fetchers-google.desc]="ユーザ操作起因の取得（google系）"

    # --- 用途はGoogle未公表。Gemini の Deep Research 等の候補だが裏は取れていない ---
    # --- 実測 12件と極小 ---
    [google-agents.url]="https://developers.google.com/static/crawling/ipranges/user-triggered-agents.json"
    [google-agents.desc]="用途はGoogle未公表。Gemini の候補。要調査"
)

# ---- 設定ここまで ----------------------------------------------------------

. "$(cd "$(dirname "$0")" && pwd)/lib/crawler-ip.lib.sh"

func_runNode "$@"
