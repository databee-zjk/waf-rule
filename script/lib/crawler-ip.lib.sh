#!/usr/bin/env bash
#
# ============================================================================
# crawler-ip.lib.sh — クローラIP取得の共通ライブラリ
# ============================================================================
#
# 【用途】
#   各社の公開JSONからIPレンジを取得する処理を1箇所にまとめたもの。
#   get-google-ip.sh / get-bing-ip.sh / get-openai-ip.sh / get-claude-ip.sh
#   から source して使う。
#
# 【このファイルが存在する理由】
#   取得の手順（HTTP取得・JSON解析・出力）を1箇所にまとめるため。
#   取得元のURLは各主体スクリプトが自分で持つ。ここには置かない。
#   URLはその主体の資産であり、集約すると主体スクリプトが単体で完結しなくなるため。
#   → Google の URL が変わったら get-google-ip.sh だけを直す。
#
# 【判定は「取れたか / 取れていないか」だけ】
#   件数の多寡は判断しない。公開元が出した件数を正とみなす。
#   こちらで「何件あるべきか」を決め打ちすると、公開元が正当に増減しただけで
#   誤検知し、そのたびに期待値の保守が必要になる。
#   「取れたが異常に少ない」場合の防護は waf-ipset.sh 側にある
#   （MAX_SHRINK_PERCENT。現在のIPSetとの相対比較なので決め打ちが要らない）。
#
# 【呼び出し側が定義すべき変数】
#   SOURCES        取得元を定義した連想配列（declare -A）。キーは <名前>.url / <名前>.desc
#   NODE_NAME      表示用の名前（例: "Google"）
#   NODE_DEFAULT   オプション無しの時に取得する取得元名（空白区切り）
#   NODE_ALL       --all の時に取得する取得元名（空白区切り）
#   定義したうえで func_runNode "$@" を呼ぶ。
#
# 【単体では実行しない】
#   source 専用。直接実行しても何もしない。
#
# [zjk 2026-09-18 AI補助]
# ============================================================================


# ログ関数（func_info / func_error / func_errorDetail）を使うため共通設定を読む。
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.sh"


# ---- 取得の動作設定（改这里）------------------------------------------------
#
# ここには「取得の振る舞い」だけを置く。
# 取得元のURLは各主体スクリプトが自分で持つ（ここには書かない）。
#   → Google の URL が変わったら get-google-ip.sh だけを直せばよい。
#   → 各主体スクリプトは単体で完結し、それ一本で実行できる。
#
# curl のタイムアウト秒数。各社のエンドポイントは通常1秒以内に応答する。
CURL_TIMEOUT=20

# 取得時に名乗る User-Agent。既定のままだと弾く相手がいるため明示する。
CURL_USER_AGENT="Mozilla/5.0 (compatible; waf-ipset-sync/1.0)"

# ---- 設定ここまで ----------------------------------------------------------



# ============================================================================
# 節点スクリプト用の入口
# ============================================================================

# func_runNode
#   入参: コマンドライン引数すべて
#         （呼び出し側で NODE_NAME / NODE_DEFAULT / NODE_ALL を定義しておくこと）
#   出参: CIDR を1行1件で標準出力
#   備考: 複数の取得元をまとめて取り、重複を除いて出す。
#         1つでも取得に失敗したら、途中結果を出さずに中止する。
func_runNode() {
    local targets="$NODE_DEFAULT"
    local only=""
    local version="ipv4"

    # 引数を先頭から1つずつ処理する。
    #   $#     … まだ処理していない引数の残り個数
    #   shift  … 先頭の引数を捨てて、残りを1つ前へずらす（$# が1減る）
    # つまり「引数が無くなるまで、先頭を1つずつ見ていく」という繰り返し。
    # 値を取るオプション（--only など）は shift を2回して、値も一緒に消費する。
    while [ $# -gt 0 ]; do
        case "$1" in
            --ipv4) version="ipv4"; shift ;;
            --ipv6) version="ipv6"; shift ;;
            --all)  targets="$NODE_ALL"; shift ;;
            --only)
                shift
                if [ $# -eq 0 ]; then
                    func_error "--only の後に取得元名を指定してください。"
                    exit 2
                fi
                only="$1"
                shift
                ;;
            --list)
                func_showNodeList
                exit 0
                ;;
            -h|--help)
                func_showNodeUsage
                exit 0
                ;;
            *)
                func_error "不明なオプション: [$1]"
                func_error "使い方を見るには: $(basename "$0") --help"
                exit 2
                ;;
        esac
    done

    if [ -n "$only" ]; then
        if ! func_isNodeSource "$only"; then
            func_error "[$only] は ${NODE_NAME} の取得元ではありません。"
            func_error "一覧を見るには: $(basename "$0") --list"
            exit 2
        fi
        targets="$only"
    fi

    func_info "対象: ${NODE_NAME}（$version）"

    # bash には块作用域が無く、local は関数全体に効く。
    # ループの中で宣言すると「ループ内だけ有効」に見えて誤解を招くため、外で宣言する。
    local src
    local -a all_cidrs=()
    local -a one=()

    for src in $targets; do
        one=()
        # mapfile   … 出力を「1行＝1要素」として配列に読み込む
        # < <(...)  … コマンドの出力をファイルのように読む書き方（プロセス置換）
        # 合わせて「func_fetchSource の出力を1行ずつ配列 one に入れる」という意味。
        mapfile -t one < <(func_fetchSource "$src" "$version")
        # func_fetchSource はサブシェルのため、失敗を終了コードで受け取れない。
        # 0件は func_checkNotEmpty が止めているので、ここに来て0件なら取得失敗とみなす。
        if [ "${#one[@]}" -eq 0 ]; then
            if [ "$version" = "ipv6" ]; then
                func_info "  $src: IPv6 は0件（この取得元では正常）"
                continue
            fi
            func_error "[$src] の取得に失敗しました。データは出力しません。"
            exit 1
        fi
        all_cidrs+=("${one[@]}")
    done

    if [ "${#all_cidrs[@]}" -eq 0 ]; then
        if [ "$version" = "ipv6" ]; then
            func_info "合計: 0 件（${NODE_NAME} は IPv6 を公開していません）"
            return 0
        fi
        func_error "1件も取得できませんでした。"
        exit 1
    fi

    local -a uniq=()
    mapfile -t uniq < <(printf '%s\n' "${all_cidrs[@]}" | sort -u)

    func_info "合計: ${#uniq[@]} 件（重複除去後）"
    printf '%s\n' "${uniq[@]}"
}

# func_isNodeSource
#   入参: $1=取得元の名前
#   出参: 終了コード 0=この節点の取得元である / 1=違う
func_isNodeSource() {
    local s
    for s in $NODE_ALL; do
        [ "$s" = "$1" ] && return 0
    done
    return 1
}

# func_showNodeUsage
#   入参: なし / 出参: 使い方を標準エラーに表示
func_showNodeUsage() {
    local me
    me=$(basename "$0")
    cat >&2 <<USAGE
使い方: ./${me} [オプション]

オプション:
  （無指定）      既定の取得元を取得する（${NODE_DEFAULT}）
  --all           ${NODE_NAME} の全取得元を取得する
  --only <名前>   取得元を1つだけ指定する
  --ipv4          IPv4 のみ出力（既定）
  --ipv6          IPv6 のみ出力
  --list          ${NODE_NAME} の取得元一覧を表示
  -h, --help      この使い方を表示

出力:
  標準出力に CIDR を1行1件。進捗と警告は標準エラーへ出すため、
  そのままファイルへリダイレクトすれば純粋なIPリストになる。

例:
  ./${me}                  既定の構成で取得
  ./${me} --all --ipv6     全取得元の IPv6
  ./${me} > ip.txt         ファイルに保存
USAGE
}

# func_showNodeList
#   入参: なし / 出参: この節点の取得元一覧を標準出力
func_showNodeList() {
    echo "${NODE_NAME} の取得元:"
    echo
    printf '  %-24s %-6s %s\n' "名前" "既定" "説明"
    printf '  %-24s %-6s %s\n' "------------------------" "------" "----------------------------------------"
    local s mark
    for s in $NODE_ALL; do
        mark=" "
        case " $NODE_DEFAULT " in *" $s "*) mark="○" ;; esac
        printf '  %-24s %-6s %s\n' "$s" "$mark" "$(func_getSourceField "$s" desc)"
    done
    echo
    echo "○ = オプション無しの時に取得される取得元"
}


# ============================================================================
# 取得と抽出
# ============================================================================

# func_fetchSource
#   入参: $1=取得元の名前, $2=ipv4 または ipv6
#   出参: CIDR を1行1件で標準出力。失敗時は何も出さずに終了コード1
func_fetchSource() {
    local name="$1" version="$2"
    local url desc
    url=$(func_getSourceField "$name" url)
    desc=$(func_getSourceField "$name" desc)

    if [ -z "$url" ]; then
        func_error "不明な取得元: [$name]"
        return 1
    fi

    func_info "  取得中: $name （$desc）"

    local body
    body=$(func_fetchUrl "$url") || return 1

    local -a cidrs=()
    mapfile -t cidrs < <(func_extractPrefixes "$body" "$version")

    func_checkNotEmpty "${#cidrs[@]}" "$name" "$version" || return 1

    func_info "  $name: ${#cidrs[@]} 件"

    # 0件のまま printf に渡すと、引数が無くても書式が1回実行されて空行が1行出る。
    # 呼び出し側が「1件取れた」と誤認するため、ここで打ち切る。
    # （IPv4 の0件は func_checkNotEmpty が既に弾いている。ここに来るのは IPv6 の0件のみ）
    if [ "${#cidrs[@]}" -eq 0 ]; then
        return 0
    fi

    printf '%s\n' "${cidrs[@]}"
}

# func_getSourceField
#   入参: $1=取得元の名前, $2=項目名（url / desc）
#   出参: 該当する値を標準出力。定義が無ければ空文字
#   備考: 呼び出し側が定義した連想配列 SOURCES から引く。
#         例: SOURCES[bing.url] → "https://www.bing.com/toolbox/bingbot.json"
func_getSourceField() {
    printf '%s' "${SOURCES[${1}.${2}]:-}"
}

# func_fetchUrl
#   入参: $1=URL
#   出参: レスポンス本文を標準出力。HTTP 200 以外なら終了コード1
func_fetchUrl() {
    local url="$1"
    local response curl_exit http_code body

    # 一時ファイルを使わず、本文の末尾にHTTPステータスを付けて受け取る。
    # 一時ファイルの後始末が不要になり、cron で中断された時のゴミも残らない。
    response=$(curl -s -w '\n%{http_code}' -m "$CURL_TIMEOUT" -A "$CURL_USER_AGENT" "$url")
    curl_exit=$?

    # curl 自体が失敗した場合（通信できていない）。
    # cron では対話シェルと環境変数が違うため、ここで落ちることが実際にある。
    if [ "$curl_exit" -ne 0 ]; then
        func_error "curl の実行に失敗しました（curl 終了コード: $curl_exit）"
        func_error "URL: $url"
        case "$curl_exit" in
            5)  func_error "  原因: プロキシのホスト名を解決できない。http_proxy / https_proxy を確認。" ;;
            6)  func_error "  原因: ホスト名を解決できない。DNS設定・ネットワーク接続を確認。" ;;
            7)  func_error "  原因: 接続できない。ファイアウォールまたはプロキシ設定を確認。" ;;
            28) func_error "  原因: ${CURL_TIMEOUT}秒でタイムアウト。回線または相手側の問題。" ;;
            35) func_error "  原因: SSL接続に失敗。TLSバージョンまたは証明書ストアを確認。" ;;
            60) func_error "  原因: サーバ証明書を検証できない。CA証明書または端末の時刻を確認。" ;;
            *)  func_error "  原因: curl のマニュアルで終了コード $curl_exit を確認してください。" ;;
        esac
        func_error "  ※ cron から実行している場合、対話シェルとは環境変数（特にプロキシ）が異なります。"
        return 1
    fi

    http_code="${response##*$'\n'}"
    body="${response%$'\n'*}"

    # 通信はできたが、期待した応答ではない場合
    if [ "$http_code" != "200" ]; then
        func_error "HTTPステータスが 200 ではありません: $http_code"
        func_error "URL: $url"
        case "$http_code" in
            301|302|307|308)
                func_error "  原因: リダイレクト。公開元がURLを変更した可能性が高い。"
                func_error "  対処: ../ip-*.md の出典を確認し、本スクリプト先頭の SOURCES 表を更新する。"
                func_error "       （Google は 2026-03 に実際にURLを変更しています）" ;;
            403)
                func_error "  原因: アクセス拒否。User-Agent で弾かれている可能性がある。"
                func_error "  対処: lib/crawler-ip.lib.sh の CURL_USER_AGENT を見直す。" ;;
            404)
                func_error "  原因: 存在しない。URLが変更または廃止された可能性が高い。"
                func_error "  対処: ../ip-*.md の出典を確認し、SOURCES 表を更新する。" ;;
            5*)
                func_error "  原因: 公開元のサーバエラー。こちら側の問題ではない。"
                func_error "  対処: 時間をおいて再実行する。継続するなら公開元の障害情報を確認。" ;;
            000)
                func_error "  原因: 応答を受け取れていない。接続が切断された可能性がある。" ;;
            *)
                func_error "  対処: ブラウザや curl で直接URLを開き、何が返るか確認する。" ;;
        esac
        return 1
    fi

    printf '%s' "$body"
}

# func_extractPrefixes
#   入参: $1=JSON本文, $2=ipv4 または ipv6
#   出参: CIDR を1行1件で標準出力（整列・重複除去済み）
#   備考: jq を使わずに済ませるため、"ipv4Prefix": "..." を正規表現で拾う。
#         各社とも構造が同一（creationTime + prefixes）なので共通で扱える。
func_extractPrefixes() {
    local body="$1" version="$2"
    local key
    if [ "$version" = "ipv6" ]; then key="ipv6Prefix"; else key="ipv4Prefix"; fi

    echo "$body" \
        | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
        | sed -e "s/.*:[[:space:]]*\"//" -e 's/"$//' \
        | grep -v '^$' \
        | sort -u
}

# func_checkNotEmpty
#   入参: $1=実際の件数, $2=取得元の名前, $3=ipv4 または ipv6
#   出参: 終了コード 0=正常 / 1=異常
#   備考: 判定は「取れたか / 取れていないか」だけ。件数の多寡は判断しない。
#         公開元が出した件数が正だとみなす。こちらで「何件あるべきか」を
#         決め打ちすると、公開元が正当に増減しただけで誤検知する。
#         なお「取れたが異常に少ない」場合の防護は waf-ipset.sh 側にある
#         （MAX_SHRINK_PERCENT。現在のIPSetとの相対比較なので決め打ちが要らない）。
func_checkNotEmpty() {
    local actual="$1" name="$2" version="$3"

    # IPv6 を公開していない取得元があるため、IPv6 の0件は正常として扱う
    if [ "$version" = "ipv6" ]; then
        return 0
    fi

    if [ "$actual" -eq 0 ]; then
        func_error "[$name] から1件も取得できませんでした。"
        func_error "  HTTPは成功しているため、JSONの構造が変わった可能性があります。"
        func_error "  対処: URLをブラウザで開き、prefixes / ipv4Prefix というキーがあるか確認する。"
        return 1
    fi

    return 0
}


# ============================================================================
# 表示の補助
# ============================================================================
#
# func_info / func_error / func_errorDetail は config.sh で定義している。
# 進捗は標準エラーへ出す。標準出力はCIDRだけにして、パイプで繋げるようにするため。
# crontab で 2>&1 に落とした時に、どのスクリプトがいつ出したログか分かる書式。
