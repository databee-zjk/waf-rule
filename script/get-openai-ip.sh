#!/usr/bin/env bash
#
# ============================================================================
# get-openai-ip.sh — OpenAI が公開しているクローラIPを取得する
# ============================================================================
#
# 【用途】
#   OpenAI公式の3つのJSONから IPレンジを取得し、CIDR を1行1件で出力する。
#   waf-ipset.sh にパイプでそのまま渡せる形式。
#
# 【OpenAI は用途別に3つ公開している。ここが本件の判断ポイント】
#   openai-gptbot         GPTBot。モデル学習用のクロール
#   openai-searchbot      OAI-SearchBot。ChatGPT検索のインデックス作成
#   openai-chatgpt-user   ChatGPT-User。ユーザが URL を渡した時の取得
#
#   分かれているため、「AI学習には使わせないが、AI検索結果には載せたい」
#   という出し分けができる。6社の中で唯一これが可能。
#   → 遮断目的で使う場合、3つをまとめて扱ってはいけない。
#
# 【既定の構成をこうしている理由】
#   既定は openai-searchbot のみ（学習用の GPTBot は方針未定のため既定に入れていない）。
#   学習用（gptbot）とユーザ操作起因（chatgpt-user）は、
#   許可するか遮断するかの方針が未決のため、意図的に既定から外している。
#   方針が決まったら NODE_DEFAULT を変更すること。
#   判断材料は ../report.ja.md の6章を参照。
#
# 【用法（最もよく使う形）】
#   ./get-openai-ip.sh                          既定（検索用のみ）を取得
#   ./get-openai-ip.sh --all                    3種すべて
#   ./get-openai-ip.sh --only openai-gptbot     学習用だけ（遮断リスト作成用）
#   ./get-openai-ip.sh --list                   取得元の一覧を表示
#   ./get-openai-ip.sh > openai.txt             ファイルに保存
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
#   OpenAI の公開エンドポイントへの HTTPS GET のみ。$0。
#   認証不要・レート制限の明示なし。1日数回程度の取得で問題になることはない。
#
# [zjk 2026-09-18 AI補助]
# ============================================================================

set -u

# ---- 本スクリプトの設定（改这里）------------------------------------------

# 表示用の名前。
NODE_NAME="OpenAI"

# オプション無しの時に取得する取得元。空白区切り。
# 学習用（openai-gptbot）を含めるかは方針次第。理由は上のコメント参照。
NODE_DEFAULT="openai-searchbot"

# --all の時に取得する取得元。OpenAI が公開している全3ファイル。
NODE_ALL="openai-gptbot openai-searchbot openai-chatgpt-user"

# 取得元の定義。取得元1つにつき url / desc の2項目。
#   url  … 公開JSONのURL
#   desc … ログに出す説明
#
# 3ファイルの使い分けが本主体の肝。
# 「学習には使わせないが、AI検索には載りたい」は、この分割があるから実現できる。

declare -A SOURCES=(
    # --- モデル学習用のクロール。学習させたくないならこれを拒否する ---
    # --- 2026-09-18 実測 21件。約11ヶ月更新されておらず安定している ---
    [openai-gptbot.url]="https://openai.com/gptbot.json"
    [openai-gptbot.desc]="GPTBot（モデル学習用のクロール）"

    # --- ChatGPT検索のインデックス用。検索結果に載りたいなら許可する ---
    # --- 2026-09-18 実測 39件。約8ヶ月更新されておらず安定している ---
    [openai-searchbot.url]="https://openai.com/searchbot.json"
    [openai-searchbot.desc]="OAI-SearchBot（ChatGPT検索のインデックス）"

    # --- ユーザがChatGPT上でリンクを開いた等、人の操作起因の取得 ---
    # --- 2026-09-18 実測 219件。3つの中でこれだけ毎日更新されている ---
    [openai-chatgpt-user.url]="https://openai.com/chatgpt-user.json"
    [openai-chatgpt-user.desc]="ChatGPT-User（ユーザ操作起因の取得）"
)

# ---- 設定ここまで ----------------------------------------------------------

. "$(cd "$(dirname "$0")" && pwd)/lib/crawler-ip.lib.sh"

func_runNode "$@"
