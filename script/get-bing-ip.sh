#!/usr/bin/env bash
#
# ============================================================================
# get-bing-ip.sh — Microsoft が公開している Bingbot のIPを取得する
# ============================================================================
#
# 【用途】
#   Microsoft公式の bingbot.json から IPレンジを取得し、CIDR を1行1件で出力する。
#   waf-ipset.sh にパイプでそのまま渡せる形式。
#
# 【Copilot について】
#   Copilot 専用のIPリストは存在しない。Bingbot の基盤を共用しているため、
#   本スクリプトの出力に含まれる。Yahoo / DuckDuckGo も同じ基盤。
#   「CopilotだけをIPで止める」と Bing検索のインデックスも失う。
#   詳細は ../ip-copilot.md を参照。
#
# 【注意: このリストは2年8ヶ月更新されていない】
#   bingbot.json の creationTime は 2024-01-03 のまま（2026-09-18 実測）。
#   許可リストとして使う場合、Microsoft が新しいIPを使い始めていれば
#   正規の Bingbot を誤って遮断する。同時に Copilot の通信も同じだけ取りこぼす。
#   → IPリスト単独に依存せず、逆引きDNS（*.search.msn.com）の検証を併用すること。
#   詳細は ../report.ja.md の課題① を参照。
#
# 【用法（最もよく使う形）】
#   ./get-bing-ip.sh                取得（IPv4）
#   ./get-bing-ip.sh --ipv6         IPv6（Microsoft は未公開のため0件になる）
#   ./get-bing-ip.sh --list         取得元の一覧を表示
#   ./get-bing-ip.sh > bing.txt     ファイルに保存
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
#   Microsoft の公開エンドポイントへの HTTPS GET のみ。$0。
#   認証不要・レート制限の明示なし。1日数回程度の取得で問題になることはない。
#
# [zjk 2026-09-18 AI補助]
# ============================================================================

set -u

# ---- 本スクリプトの設定（改这里）------------------------------------------

# 表示用の名前。
NODE_NAME="Bing"

# オプション無しの時に取得する取得元。空白区切り。
NODE_DEFAULT="bing"

# --all の時に取得する取得元。Microsoft は用途別の分割をしていないため1つだけ。
NODE_ALL="bing"

# 取得元の定義。取得元1つにつき url / desc の2項目。
#   url  … 公開JSONのURL
#   desc … ログに出す説明
declare -A SOURCES=(
    # Microsoft は用途別に分割しておらず、公開しているのはこのJSON1本だけ。
    # 取得に失敗するようになったら ../ip-bing-bot.md の出典を確認して直す。
    #
    # 2026-09-18 実測 28件。
    # 注意: このJSONは creationTime が 2024-01-03 のまま2年8ヶ月更新されていない。
    #       件数が変わらないこと自体は異常ではないが、許可リスト用途では
    #       新しいBingbotのIPを取りこぼすリスクがある（../report.ja.md 課題①）。
    [bing.url]="https://www.bing.com/toolbox/bingbot.json"
    [bing.desc]="Bingbot（Copilot / Yahoo / DuckDuckGo も同基盤）"
)

# ---- 設定ここまで ----------------------------------------------------------

. "$(cd "$(dirname "$0")" && pwd)/lib/crawler-ip.lib.sh"

func_runNode "$@"
