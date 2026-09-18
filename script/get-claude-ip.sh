#!/usr/bin/env bash
#
# ============================================================================
# get-claude-ip.sh — Anthropic が公開している Claude のクローラIPを取得する
# ============================================================================
#
# 【用途】
#   Anthropic公式の bots.json から IPレンジを取得し、CIDR を1行1件で出力する。
#   waf-ipset.sh にパイプでそのまま渡せる形式。
#
# 【注意: UA別の分割はされていない】
#   Anthropic は3つのUA（ClaudeBot / Claude-User / Claude-SearchBot）を
#   使い分けているが、公開しているIPリストは1つだけで、UA別に分かれていない。
#   → OpenAI のような「学習用だけ遮断」はIPでは実現できない。
#   UA単位で出し分けたい場合は robots.txt 側で対応すること。
#   詳細は ../ip-claude.md を参照。
#
# 【用法（最もよく使う形）】
#   ./get-claude-ip.sh                  取得（IPv4）
#   ./get-claude-ip.sh --ipv6           IPv6
#   ./get-claude-ip.sh --list           取得元の一覧を表示
#   ./get-claude-ip.sh > claude.txt     ファイルに保存
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
#   Anthropic の公開エンドポイントへの HTTPS GET のみ。$0。
#   認証不要・レート制限の明示なし。1日数回程度の取得で問題になることはない。
#
# [zjk 2026-09-18 AI補助]
# ============================================================================

set -u

# ---- 本スクリプトの設定（改这里）------------------------------------------

# 表示用の名前。
NODE_NAME="Claude"

# オプション無しの時に取得する取得元。空白区切り。
NODE_DEFAULT="claude"

# --all の時に取得する取得元。Anthropic は用途別の分割をしていないため1つだけ。
NODE_ALL="claude"

# 取得元の定義。取得元1つにつき url / desc の2項目。
#   url  … 公開JSONのURL
#   desc … ログに出す説明
declare -A SOURCES=(
    # 旧 docs.claude.com/claudebot.json は 301。現行はこちら。
    # 注意: platform.claude.com の「IP addresses」は自社→Claude API 接続用であり、
    #       クローラのIPではない。取り違えると全く効かない（../ip-claude.md 参照）。
    #
    # 2026-09-18 実測 26件。
    [claude.url]="https://claude.com/crawling/bots.json"

    # ClaudeBot / Claude-User / Claude-SearchBot の3UAが1ファイルに混在しており、
    # UA別の出し分けはIPだけでは不可能（WAFルール側で文字列条件との併用が必要）。
    [claude.desc]="ClaudeBot / Claude-User / Claude-SearchBot（UA別の分割なし）"
)

# ---- 設定ここまで ----------------------------------------------------------

. "$(cd "$(dirname "$0")" && pwd)/lib/crawler-ip.lib.sh"

func_runNode "$@"
