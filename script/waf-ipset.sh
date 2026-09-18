#!/usr/bin/env bash
#
# ============================================================================
# waf-ipset.sh — AWS WAF の IPSet（許可/拒否IPリスト）を操作する
# ============================================================================
#
# 【用途】
#   AWS WAF の IPSet に対して、IPアドレス（CIDR）の追加・削除・全件置換を行う。
#   操作対象は IPSet であり、Web ACL ではない（Web ACL は IPSet を参照するだけ）。
#
# 【用法（最もよく使う形）】
#   ./waf-ipset.sh list                              現在の登録内容を表示
#   ./waf-ipset.sh add 203.0.113.5/32                1件追加（模擬実行）
#   ./waf-ipset.sh add 203.0.113.5/32 --apply        1件追加（本当に書き込む）
#   ./waf-ipset.sh add 203.0.113.0/24 198.51.100.0/24 --apply   複数件追加
#   ./waf-ipset.sh add -f list.txt --apply           ファイルから追加
#   ./waf-ipset.sh del 203.0.113.5/32 --apply        削除
#   ./waf-ipset.sh replace -f list.txt --apply       全件置換（既存は全て消える）
#
#
# 【基本の使い方 — 取得スクリプトとパイプで繋ぐ】
#
#   <取得スクリプト> | ./waf-ipset.sh replace -f - --IPSET_NAME=<名前> --apply
#
#   実例:
#     ./get-google-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=google-list --apply
#     ./get-bing-ip.sh   | ./waf-ipset.sh replace -f - --IPSET_NAME=bing-list   --apply
#     ./get-claude-ip.sh | ./waf-ipset.sh replace -f - --IPSET_NAME=claude-list --apply
#
#   主体ごとに IPSet を分けておくと、Google は許可・GPTBot は拒否、のように
#   別々の方針を当てられる。1つにまとめると、この出し分けができなくなる。
#
# 【役割分担】
#   取得スクリプト側の責任 … 正しいCIDRの一覧を標準出力に出すこと。
#                             出せないときは0件を出さず、異常終了すること。
#   本スクリプトの責任     … 渡された一覧を検証し、IPSet へ正しく反映すること。
#
#   本スクリプトが行う検証（パイプの上流が何であっても効く）:
#     1. CIDR の形式・範囲・ネットワークアドレスであること
#     2. 空の入力を拒否する（上流が失敗して何も出さなかった場合）
#     3. replace で件数が急減していないか（MAX_SHRINK_PERCENT）
#     4. AWS の上限件数を超えていないか
#     5. --apply が無ければ書き込まない
#
#   シェルのパイプは上流の終了コードを下流に伝えないが、
#   上流が失敗した結果は「空」か「異常に少ない」のどちらかになるため、
#   2 と 3 で止まる。上流の成否そのものを見たい場合は PIPESTATUS を確認すること。
#
# 【入参】
#   第1引数   サブコマンド: list | add | del | replace
#   第2引数～ CIDR を直接指定、または -f <ファイル|->（1行1件、空行と # 行は無視）
#   オプション:
#     --apply    実際に書き込む。付けない限り必ず模擬実行（安全側の既定）
#     --pipe     自動化用。余計な表示をせず、Enter待ちもしない
#
# 【出参】
#   標準出力: list のIPリストのみ（データ専用。パイプで次へ渡せるようにするため）
#   標準エラー: 進捗・差分・実行記録・エラー（crontab では 2>&1 でログに残す）
#   ファイル: analysis/update-<IPSet名>.json のみ（aws CLI へ渡すため技術的に必要）。
#             毎回上書きし、履歴は残さない。現在の内容は list で、実行記録はログで確認する。
#   終了コード: 0=変更あり / 3=変更なし（既に目的の状態） / 2=引数エラー / 1=実行エラー
#
# 【設定の上書き】
#   すべての設定は「--項目名=値」で一時的に上書きできる。設定項目名がそのまま引数名。
#   別のIPSetや別リージョンに同じスクリプトを使い回すための仕組み。
#     ./waf-ipset.sh list --IPSET_NAME=other-list
#     ./waf-ipset.sh list --IPSET_SCOPE=CLOUDFRONT --AWS_REGION=us-east-1
#     ./waf-ipset.sh add 203.0.113.0/24 --AWS_PROFILE_NAME=prod --apply
#   指定できる項目は --help で一覧表示する。
#
# 【実行環境】
#   Git Bash（Windows）/ bash 4.4 以上。aws CLI v2 が必要。jq は不要。
#   同じディレクトリに config.sh があること（共通設定と共通関数）。
#
# 【費用】
#   aws wafv2 list-ip-sets / get-ip-set / update-ip-set … すべて $0（課金対象外）
#   本スクリプトの実行によって発生する AWS 費用はない。
#   ※ WAF 自体の月額（Web ACL $5.00/月、ルール $1.00/月）は本スクリプトとは無関係に発生する。
#
# 【制限】
#   IPv4 のみ対応。IPSet が IPv6 の場合はエラーで停止する（誤操作防止のため）。
#
# [zjk 2026-09-18 AI補助]
# ============================================================================

set -u

# ---- 本スクリプトの設定（改这里）------------------------------------------
#
# AWS_PROFILE_NAME / AWS_REGION / LOG_DIR は複数のスクリプトで共通のため
# config.sh にある。ここには本スクリプト固有の設定だけを置く。
#
# すべての設定は「--項目名=値」で一時的に上書きできる（--help で一覧）。
#   例: ./waf-ipset.sh list --IPSET_NAME=other-list --AWS_REGION=us-east-1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/config.sh"

# IPSet のスコープ。CloudFront に紐づく WAF なら CLOUDFRONT、
# ALB / API Gateway に紐づくなら REGIONAL。間違えると IPSet が見つからない。
IPSET_SCOPE="REGIONAL"

# 操作対象の IPSet 名。AWS が生成する ID（UUID）は名前から自動で解決するので設定不要。
# スコープ内で名前は一意。コンソールの IP sets 画面に出ている名前をそのまま書く。
IPSET_NAME="crawler-allow-list"

# 許可する最小プレフィックス長。これより広い（数字が小さい）指定は拒否する。
# 16 なら /15 以下を拒否＝1件あたり最大 65,536 IP まで。
# 小さくすると、1行の書き間違いで許可される範囲が一気に広がる。
MIN_PREFIX_LEN=16

# IPSet に登録できる件数の上限（AWS の固定クォータ）。これを超える操作は事前に止める。
MAX_ADDRESSES=10000

# replace で件数がこの割合を超えて減る場合、異常とみなして中止する（単位: %）。
# 30 なら「現在100件 → 新70件未満」で中止。
#
# 取得元の仕様変更や障害で件数が激減したリストを、そのまま流し込むのを止めるための防波堤。
# パイプで使う場合、上流の異常をこちらで検知できる唯一の手段になる。
#   例: ./get-google-ip.sh | ./waf-ipset.sh replace -f - --apply
#       Google 側が壊れて10件しか返さなくても、ここで止まる。
#
# add / del には適用しない（人が明示的に指定した増減のため）。
# 正当な減少だと確認できたら --MAX_SHRINK_PERCENT=100 で一時的に無効化できる。
MAX_SHRINK_PERCENT=30

# ---- 設定ここまで ----------------------------------------------------------

# 「--項目名=値」で上書きを許す設定の一覧。
# ここに無い名前を指定した場合はエラーにする（打ち間違いを黙って無視しないため）。
OVERRIDABLE="AWS_PROFILE_NAME AWS_REGION IPSET_SCOPE IPSET_NAME MIN_PREFIX_LEN MAX_ADDRESSES MAX_SHRINK_PERCENT LOG_DIR"

SCRIPT_NAME="$(basename "$0")"
IS_PIPE=0
IS_APPLY=0
SUBCOMMAND=""
declare -a INPUT_CIDRS=()

# 取得した IPSet の情報を入れる（func_getIpSet が設定する）
IPSET_ID=""
IPSET_LOCK_TOKEN=""
IPSET_DESCRIPTION=""
IPSET_IP_VERSION=""
declare -a CURRENT_ADDRESSES=()


# ============================================================================
# main — 全体の流れ
# ============================================================================
main() {
    func_parseArgs "$@"

    if [ "$SUBCOMMAND" = "list" ]; then
        func_resolveIpSetId
        func_getIpSet
        func_printList
        exit 0
    fi

    # add / del / replace の共通処理
    func_validateAllInputs
    func_resolveIpSetId
    func_getIpSet

    local -a new_addresses=()
    # mapfile   … 出力を「1行＝1要素」として配列に読み込む
    # < <(...)  … コマンドの出力をファイルのように読む書き方（プロセス置換）
    mapfile -t new_addresses < <(func_buildNewAddresses)

    func_printDiff "${new_addresses[@]}"

    if func_isSameSet "${new_addresses[@]}"; then
        func_info "変更はありません（既に目的の状態です）。書き込みは行いません。"
        exit 3
    fi

    func_checkMaxAddresses "${#new_addresses[@]}"
    func_checkShrink "${#new_addresses[@]}"

    if [ "$IS_APPLY" -eq 1 ]; then
        func_updateIpSetApply "${new_addresses[@]}"
    else
        func_updateIpSetDryRun "${new_addresses[@]}"
    fi

    exit 0
}


# ============================================================================
# 引数の解析と検証
# ============================================================================

# func_showUsage
#   入参: なし / 出参: なし（使い方を標準エラーに表示）
func_showUsage() {
    cat >&2 <<'USAGE'
使い方: waf-ipset.sh <サブコマンド> [CIDR...] [-f ファイル] [--apply] [--pipe]

サブコマンド:
  list                  現在の登録内容を表示する
  add     <CIDR...>     指定したIPを追加する（既にあるものは無視）
  del     <CIDR...>     指定したIPを削除する（無いものは無視）
  replace -f <ファイル>  全件を置き換える（既存の登録は全て消える）

オプション:
  --apply   実際に書き込む。付けない場合は必ず模擬実行のみ
  --pipe    余計な表示をせず、終了時にEnter待ちをしない（自動化用）

例:
  ./waf-ipset.sh list
  ./waf-ipset.sh add 203.0.113.5/32 --apply
  ./waf-ipset.sh add -f allow.txt --apply
  ./waf-ipset.sh del 203.0.113.5/32 --apply
  ./waf-ipset.sh list --IPSET_NAME=other-list --AWS_REGION=us-east-1
USAGE
    echo >&2
    func_showOverridable "$OVERRIDABLE"
    echo >&2
    echo "現在の値: AWS_REGION=$AWS_REGION IPSET_SCOPE=$IPSET_SCOPE IPSET_NAME=$IPSET_NAME" >&2
}

# func_parseArgs
#   入参: コマンドライン引数すべて
#   出参: SUBCOMMAND / INPUT_CIDRS / IS_APPLY / IS_PIPE を設定
func_parseArgs() {
    if [ $# -eq 0 ]; then
        func_showUsage
        exit 2
    fi

    SUBCOMMAND="$1"
    shift

    case "$SUBCOMMAND" in
        list|add|del|replace) ;;
        -h|--help)
            func_showUsage
            exit 0
            ;;
        *)
            func_error "不明なサブコマンド: [$SUBCOMMAND]"
            func_error "指定できるのは list / add / del / replace のいずれかです。"
            exit 2
            ;;
    esac

    # 残りの引数を先頭から1つずつ処理する。
    #   $#     … まだ処理していない引数の残り個数
    #   shift  … 先頭の引数を捨てて、残りを1つ前へずらす（$# が1減る）
    # つまり「引数が無くなるまで、先頭を1つずつ見ていく」という繰り返し。
    # 値を取るオプション（-f など）は shift を2回して、値も一緒に消費する。
    while [ $# -gt 0 ]; do
        case "$1" in
            --apply) IS_APPLY=1; shift ;;
            --pipe)  IS_PIPE=1;  shift ;;
            -f)
                if [ $# -lt 2 ]; then
                    func_error "-f の後にファイル名がありません。"
                    exit 2
                fi
                mapfile -t -O "${#INPUT_CIDRS[@]}" INPUT_CIDRS < <(func_readCidrFile "$2")
                shift 2
                ;;
            --*=*)
                if ! func_applyConfigOverride "$1" "$OVERRIDABLE"; then
                    func_error "上書きできない設定です: [$1]"
                    func_showOverridable "$OVERRIDABLE"
                    exit 2
                fi
                shift
                ;;
            -*)
                func_error "不明なオプション: [$1]"
                exit 2
                ;;
            *)
                INPUT_CIDRS+=("$1")
                shift
                ;;
        esac
    done

    # サブコマンドごとの引数の要不要をチェックする
    if [ "$SUBCOMMAND" = "list" ]; then
        if [ "${#INPUT_CIDRS[@]}" -gt 0 ]; then
            func_error "list は CIDR を取りません。"
            exit 2
        fi
        return
    fi

    if [ "${#INPUT_CIDRS[@]}" -eq 0 ]; then
        func_error "$SUBCOMMAND には CIDR の指定が必要です。"
        func_error "正しい形式: ./waf-ipset.sh $SUBCOMMAND 203.0.113.0/24 [...]  または  -f ファイル"
        exit 2
    fi

    # replace は「既存が全て消える」操作なので、うっかり1件指定を防ぐ
    if [ "$SUBCOMMAND" = "replace" ] && [ "${#INPUT_CIDRS[@]}" -lt 2 ]; then
        func_error "replace は既存を全て置き換える操作です。1件だけの指定は事故の可能性が高いため拒否します。"
        func_error "本当に1件だけにする場合は、その1件だけを書いたファイルを -f で指定してください。"
        exit 2
    fi
}

# func_readCidrFile
#   入参: $1=ファイルパス。"-" を指定すると標準入力から読む
#   出参: CIDR を1行1件で標準出力（空行と # 以降は除外）
func_readCidrFile() {
    local file="$1"
    if [ "$file" = "-" ]; then
        sed -e 's/#.*//' -e 's/[[:space:]]//g' | grep -v '^$'
        return
    fi
    if [ ! -f "$file" ]; then
        func_error "ファイルが見つかりません: $file"
        exit 2
    fi
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$file" | grep -v '^$'
}

# func_validateAllInputs
#   入参: なし（INPUT_CIDRS を見る）
#   出参: なし。1件でも不正なら全体を中止する（部分適用を避けるため）
func_validateAllInputs() {
    local cidr
    local ng=0
    for cidr in "${INPUT_CIDRS[@]}"; do
        if ! func_validateCidr "$cidr"; then
            ng=$((ng + 1))
        fi
    done
    if [ "$ng" -gt 0 ]; then
        func_error "不正な指定が ${ng} 件あります。1件も書き込まずに中止しました。"
        exit 2
    fi

    # 重複指定を検出して知らせる（処理は続行する）
    local dup
    dup=$(printf '%s\n' "${INPUT_CIDRS[@]}" | sort | uniq -d)
    if [ -n "$dup" ]; then
        func_info "※ 入力に重複があります（1件として扱います）: $(echo "$dup" | tr '\n' ' ')"
    fi
}

# func_validateCidr
#   入参: $1=検査するCIDR文字列
#   出参: 終了コード 0=正しい / 1=不正（理由を標準エラーに出す）
func_validateCidr() {
    local cidr="$1"

    if [[ "$cidr" == *:* ]]; then
        func_error "[$cidr] IPv6 には未対応です。本スクリプトは IPv4 のみを扱います。"
        return 1
    fi

    if ! [[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]]; then
        func_error "[$cidr] 形式が違います。正しい形式: 203.0.113.0/24（プレフィックス長は必須）"
        return 1
    fi

    local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}"
    local o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}"
    local prefix="${BASH_REMATCH[5]}"

    local o
    for o in "$o1" "$o2" "$o3" "$o4"; do
        if [ "$((10#$o))" -gt 255 ]; then
            func_error "[$cidr] IPアドレスの各値は 0〜255 です（$o は範囲外）。"
            return 1
        fi
    done

    if [ "$((10#$prefix))" -gt 32 ]; then
        func_error "[$cidr] プレフィックス長は 32 以下です。"
        return 1
    fi

    if [ "$((10#$prefix))" -lt "$MIN_PREFIX_LEN" ]; then
        func_error "[$cidr] 範囲が広すぎます。/$MIN_PREFIX_LEN 以上を指定してください（設定: MIN_PREFIX_LEN）。"
        return 1
    fi

    # ホスト部が 0 であること（ネットワークアドレスであること）を確認する。
    # 例: 203.0.113.5/24 は誤り。正しくは 203.0.113.0/24。
    #     AWS 側は受け付けてしまうため、意図と違う範囲が許可される事故になる。
    local ip_int mask host_bits
    ip_int=$(( (10#$o1 << 24) + (10#$o2 << 16) + (10#$o3 << 8) + 10#$o4 ))
    mask=$(( (0xFFFFFFFF << (32 - 10#$prefix)) & 0xFFFFFFFF ))
    host_bits=$(( ip_int & (~mask & 0xFFFFFFFF) ))

    if [ "$host_bits" -ne 0 ]; then
        local correct
        correct=$(func_intToIp $(( ip_int & mask )))
        func_error "[$cidr] ネットワークアドレスではありません。正しくは ${correct}/${prefix} です。"
        return 1
    fi

    return 0
}

# func_intToIp
#   入参: $1=32bit整数
#   出参: ドット区切りのIPv4文字列を標準出力
func_intToIp() {
    local n="$1"
    printf '%d.%d.%d.%d' \
        $(( (n >> 24) & 255 )) $(( (n >> 16) & 255 )) \
        $(( (n >> 8) & 255 ))  $(( n & 255 ))
}


# ============================================================================
# AWS からの取得
# ============================================================================

# func_awsCli
#   入参: aws コマンドの引数すべて
#   出参: aws の出力をそのまま返す。プロファイル/リージョンを共通で付与する。
func_awsCli() {
    local -a opts=(--region "$AWS_REGION")
    if [ -n "$AWS_PROFILE_NAME" ]; then
        opts+=(--profile "$AWS_PROFILE_NAME")
    fi
    aws "$@" "${opts[@]}"
}

# func_resolveIpSetId
#   入参: なし（IPSET_NAME / IPSET_SCOPE を使う）
#   出参: IPSET_ID を設定する
func_resolveIpSetId() {
    func_info "IPSet を検索中: 名前=$IPSET_NAME スコープ=$IPSET_SCOPE リージョン=$AWS_REGION"

    local err="${LOG_DIR}/aws-stderr-${IPSET_NAME}.tmp"
    mkdir -p "$LOG_DIR"

    IPSET_ID=$(func_awsCli wafv2 list-ip-sets \
        --scope "$IPSET_SCOPE" \
        --query "IPSets[?Name=='${IPSET_NAME}'].Id | [0]" \
        --output text 2>"$err")

    # aws CLI が出したエラーを握りつぶさない。
    # crontab では、ここを潰すと原因が永久に分からなくなる。
    if [ -s "$err" ]; then
        func_error "aws CLI の呼び出しに失敗しました（wafv2 list-ip-sets）"
        func_errorDetail "aws CLI が出力した内容:" "$err"
        func_error "よくある原因と対処:"
        func_error "  権限不足           → IAMに wafv2:ListIPSets / GetIPSet / UpdateIPSet が必要"
        func_error "  認証情報の期限切れ → aws sso login 等で取り直す"
        func_error "  プロファイル誤り   → 現在の指定: ${AWS_PROFILE_NAME:-（既定プロファイル）}"
        func_error "  リージョン誤り     → 現在の指定: ${AWS_REGION}"
        func_error "  aws CLI 未インストール → aws --version で確認"
        rm -f "$err"
        exit 1
    fi
    rm -f "$err"

    if [ -z "$IPSET_ID" ] || [ "$IPSET_ID" = "None" ]; then
        func_error "IPSet が見つかりません: [$IPSET_NAME]"
        func_error "aws CLI の呼び出し自体は成功しているため、権限や認証ではなく指定の問題です。"
        func_error "確認してください: 名前の綴り / IPSET_SCOPE（$IPSET_SCOPE）/ AWS_REGION（$AWS_REGION）"
        func_error "一覧を見るには: aws wafv2 list-ip-sets --scope $IPSET_SCOPE --region $AWS_REGION"
        exit 1
    fi
}

# func_getIpSet
#   入参: なし（IPSET_ID を使う）
#   出参: CURRENT_ADDRESSES / IPSET_LOCK_TOKEN / IPSET_DESCRIPTION / IPSET_IP_VERSION を設定
func_getIpSet() {
    local err="${LOG_DIR}/aws-stderr-${IPSET_NAME}.tmp"
    mkdir -p "$LOG_DIR"

    local raw
    if ! raw=$(func_awsCli wafv2 get-ip-set \
        --name "$IPSET_NAME" --scope "$IPSET_SCOPE" --id "$IPSET_ID" \
        --query "[LockToken, IPSet.IPAddressVersion, IPSet.Description]" \
        --output text 2>"$err"); then
        func_error "IPSet の取得に失敗しました（wafv2 get-ip-set）"
        func_errorDetail "aws CLI が出力した内容:" "$err"
        func_error "IAMに wafv2:GetIPSet の権限があるか確認してください。"
        rm -f "$err"
        exit 1
    fi
    rm -f "$err"

    IPSET_LOCK_TOKEN=$(echo "$raw" | cut -f1)
    IPSET_IP_VERSION=$(echo "$raw" | cut -f2)
    IPSET_DESCRIPTION=$(echo "$raw" | cut -f3)
    [ "$IPSET_DESCRIPTION" = "None" ] && IPSET_DESCRIPTION=""

    if [ "$IPSET_IP_VERSION" != "IPV4" ]; then
        func_error "対象の IPSet は $IPSET_IP_VERSION です。本スクリプトは IPV4 のみ対応しています。"
        exit 1
    fi

    mapfile -t CURRENT_ADDRESSES < <(func_awsCli wafv2 get-ip-set \
        --name "$IPSET_NAME" --scope "$IPSET_SCOPE" --id "$IPSET_ID" \
        --query "IPSet.Addresses[]" --output text | tr '\t' '\n' | grep -v '^$' | sort)
}


# ============================================================================
# 集合の計算と表示
# ============================================================================

# func_buildNewAddresses
#   入参: なし（SUBCOMMAND / CURRENT_ADDRESSES / INPUT_CIDRS を使う）
#   出参: 変更後のアドレス一覧を1行1件で標準出力（重複除去・整列済み）
func_buildNewAddresses() {
    case "$SUBCOMMAND" in
        add)
            { printf '%s\n' "${CURRENT_ADDRESSES[@]}"
              printf '%s\n' "${INPUT_CIDRS[@]}"; } | grep -v '^$' | sort -u
            ;;
        del)
            printf '%s\n' "${CURRENT_ADDRESSES[@]}" \
                | grep -v '^$' | sort -u \
                | grep -vxF -f <(printf '%s\n' "${INPUT_CIDRS[@]}") || true
            ;;
        replace)
            printf '%s\n' "${INPUT_CIDRS[@]}" | grep -v '^$' | sort -u
            ;;
    esac
}

# func_isSameSet
#   入参: $@=変更後のアドレス一覧
#   出参: 終了コード 0=現在と同じ / 1=違う
func_isSameSet() {
    local before after
    before=$(printf '%s\n' "${CURRENT_ADDRESSES[@]}" | grep -v '^$' | sort -u)
    after=$(printf '%s\n' "$@" | grep -v '^$' | sort -u)
    [ "$before" = "$after" ]
}

# func_printList
#   入参: なし（CURRENT_ADDRESSES を使う）
#   出参: 現在の登録内容を標準出力
func_printList() {
    if [ "$IS_PIPE" -eq 1 ]; then
        printf '%s\n' "${CURRENT_ADDRESSES[@]}"
        return
    fi
    echo >&2
    echo "IPSet: $IPSET_NAME （ID: $IPSET_ID）" >&2
    echo "登録件数: ${#CURRENT_ADDRESSES[@]} 件 / 上限 ${MAX_ADDRESSES} 件" >&2
    echo "--------------------------------------------------" >&2
    printf '%s\n' "${CURRENT_ADDRESSES[@]}"
    echo "--------------------------------------------------" >&2
}

# func_printDiff
#   入参: $@=変更後のアドレス一覧
#   出参: 追加分・削除分を標準出力（何が起きるかを実行前に見せる）
func_printDiff() {
    [ "$IS_PIPE" -eq 1 ] && return

    local before after before_n after_n
    before=$(printf '%s\n' "${CURRENT_ADDRESSES[@]}" | grep -v '^$' | sort -u)
    after=$(printf '%s\n' "$@" | grep -v '^$' | sort -u)
    before_n=$(printf '%s' "$before" | grep -c . || true)
    after_n=$(printf '%s' "$after" | grep -c . || true)

    echo >&2
    echo "=== 変更内容 ===================================" >&2
    echo "対象 IPSet : $IPSET_NAME （ID: $IPSET_ID）" >&2
    echo "操作       : $SUBCOMMAND" >&2
    echo "件数       : ${before_n} 件 → ${after_n} 件" >&2
    echo >&2
    comm -13 <(echo "$before") <(echo "$after") | sed 's/^/  [追加] /' >&2
    comm -23 <(echo "$before") <(echo "$after") | sed 's/^/  [削除] /' >&2
    echo "================================================" >&2
}

# func_checkMaxAddresses
#   入参: $1=変更後の件数
#   出参: なし。上限を超えるなら中止する
func_checkMaxAddresses() {
    if [ "$1" -gt "$MAX_ADDRESSES" ]; then
        func_error "変更後の件数が $1 件となり、AWS の上限 $MAX_ADDRESSES 件を超えます。中止しました。"
        exit 2
    fi
}

# func_checkShrink
#   入参: $1=変更後の件数
#   出参: なし。replace で件数が急減する場合は中止する
#   備考: パイプで流し込むとき、上流の異常をこちら側で検知する唯一の防護。
#         上流が「空」を返した場合は入参検証で既に弾かれるが、
#         「少ないが空ではない」場合はここでしか止められない。
func_checkShrink() {
    local new="$1"
    local current="${#CURRENT_ADDRESSES[@]}"

    # add / del は人が明示した増減なので検査しない
    [ "$SUBCOMMAND" != "replace" ] && return
    # 初回（現在0件）は比較対象がない
    [ "$current" -eq 0 ] && return
    # 増える分には問題ない
    [ "$new" -ge "$current" ] && return

    local limit=$(( current * (100 - MAX_SHRINK_PERCENT) / 100 ))
    if [ "$new" -lt "$limit" ]; then
        local pct=$(( (current - new) * 100 / current ))
        func_error "件数が大きく減少します: ${current} 件 → ${new} 件（${pct}% 減）"
        func_error "許容している減少率は ${MAX_SHRINK_PERCENT}% までです。"
        func_error "取得元の障害・仕様変更の可能性があるため、書き込まずに中止しました。"
        func_error "正当な減少だと確認できた場合は、--MAX_SHRINK_PERCENT=100 を付けて再実行してください。"
        exit 1
    fi
}


# ============================================================================
# 書き込み（模擬 / 実行）
#   2つの関数は入参・出参を同じにしてある。切り替えは main の分岐のみ。
# ============================================================================

# func_updateIpSetDryRun
#   入参: $@=変更後のアドレス一覧
#   出参: 実行されるはずの内容を表示するだけ。AWS への書き込みは行わない。
func_updateIpSetDryRun() {
    local json_file
    json_file=$(func_writeUpdateJson "$@")

    echo >&2
    echo "*** 模擬実行です。AWS には書き込んでいません。 ***" >&2
    echo >&2
    echo "送信予定のJSON: $json_file" >&2
    echo >&2
    func_printExecutionLog "模擬実行（未書き込み）" "-"
    echo >&2
    echo "--- 実際に書き込むには、同じコマンドに --apply を付けてください ---" >&2
    echo "  ./$SCRIPT_NAME $SUBCOMMAND ${INPUT_CIDRS[*]} --apply" >&2
}

# func_updateIpSetApply
#   入参: $@=変更後のアドレス一覧
#   出参: AWS に書き込む。新しい LockToken を表示する。
func_updateIpSetApply() {
    local json_file new_token
    json_file=$(func_writeUpdateJson "$@")

    local err="${LOG_DIR}/aws-stderr-${IPSET_NAME}.tmp"
    if ! new_token=$(func_awsCli wafv2 update-ip-set \
        --cli-input-json "file://${json_file}" \
        --query "NextLockToken" --output text 2>"$err"); then
        func_error "書き込みに失敗しました（wafv2 update-ip-set）"
        func_errorDetail "aws CLI が出力した内容:" "$err"
        func_error "よくある原因と対処:"
        func_error "  WAFOptimisticLockException → 他の誰かが同時に更新した。もう一度実行すれば通る"
        func_error "  AccessDeniedException      → IAMに wafv2:UpdateIPSet の権限が無い"
        func_error "  WAFLimitsExceededException → 件数がAWSの上限を超えている"
        func_error "送信したJSON: $json_file"
        rm -f "$err"
        exit 1
    fi
    rm -f "$err"

    echo >&2
    echo "*** 書き込みました。 ***" >&2
    echo >&2
    func_printExecutionLog "実行済み" "$new_token"
    echo >&2
    echo "--- 結果を確認するには ---" >&2
    echo "  ./$SCRIPT_NAME list" >&2
}

# func_writeUpdateJson
#   入参: $@=変更後のアドレス一覧
#   出参: 生成したJSONのパスを標準出力（aws --cli-input-json に渡す用）
#   備考: 件数が多いとコマンドライン長の上限に当たるため、必ずファイル経由で渡す。
func_writeUpdateJson() {
    # 固定名にして毎回上書きする。履歴は残さない。
    # 理由: 現在の登録内容は ./waf-ipset.sh list でいつでも確認でき、
    #       実行記録は標準エラーに出るので crontab のログに残る。
    #       過去のJSONを貯めても復核の役には立たず、ファイルが際限なく増えるだけ。
    # IPSet 名をファイル名に入れているのは、主体ごとに別IPSetを扱うため
    # （同時に走っても互いのファイルを壊さない）。
    local file="${LOG_DIR}/update-${IPSET_NAME}.json"
    mkdir -p "$LOG_DIR"

    {
        printf '{\n'
        printf '  "Name": "%s",\n' "$IPSET_NAME"
        printf '  "Scope": "%s",\n' "$IPSET_SCOPE"
        printf '  "Id": "%s",\n' "$IPSET_ID"
        printf '  "Description": "%s",\n' "$IPSET_DESCRIPTION"
        printf '  "LockToken": "%s",\n' "$IPSET_LOCK_TOKEN"
        printf '  "Addresses": [\n'
        local first=1 addr
        for addr in "$@"; do
            [ -z "$addr" ] && continue
            [ "$first" -eq 0 ] && printf ',\n'
            printf '    "%s"' "$addr"
            first=0
        done
        printf '\n  ]\n'
        printf '}\n'
    } > "$file"

    echo "$file"
}

# func_printExecutionLog
#   入参: $1=状態の説明, $2=更新後のLockToken（無ければ "-"）
#   出参: 実行記録を標準エラーへ出力する
#   備考: ファイルには落とさない。
#         crontab では 2>&1 でログに残り、手元で実行すれば画面に出る。
#         同じ内容を別ファイルにも書くと、ログが二重管理になり
#         analysis/ が際限なく増えるだけで復核の役には立たない。
func_printExecutionLog() {
    local status="$1" new_token="$2"

    {
        echo "=== 実行記録 ==================================="
        echo "状態          : $status"
        echo "日時          : $(date '+%Y-%m-%d %H:%M:%S %z')"
        echo "実行者        : ${USERNAME:-${USER:-unknown}}@$(hostname)"
        echo "AWSプロファイル: ${AWS_PROFILE_NAME:-（既定）}"
        echo "リージョン    : $AWS_REGION"
        echo "スコープ      : $IPSET_SCOPE"
        echo "IPSet名       : $IPSET_NAME"
        echo "IPSet ID      : $IPSET_ID"
        echo "操作          : $SUBCOMMAND"
        echo "指定された値  : ${INPUT_CIDRS[*]}"
        echo "更新前件数    : ${#CURRENT_ADDRESSES[@]}"
        echo "旧LockToken   : $IPSET_LOCK_TOKEN"
        echo "新LockToken   : $new_token"
        echo "================================================"
    } >&2
}


# ============================================================================
# 表示の補助
# ============================================================================

# func_info / func_error / func_errorDetail は config.sh で定義している。
# crontab で 2>&1 に落とした時に、どのスクリプトがいつ出したログか分かる書式にしてある。

# 終了時に Enter を待つ（エラーで落ちた時も内容が読めるようにするため）。
# NO_PAUSE=1 か --pipe が指定されている場合、または対話端末でない場合は待たない。
func_waitEnter() {
    local code=$?
    [ "$IS_PIPE" -eq 1 ] && exit $code
    [ "${NO_PAUSE:-0}" = "1" ] && exit $code
    [ ! -t 0 ] && exit $code
    echo >&2
    read -r -p "Enter を押すと終了します..." _
    exit $code
}

trap func_waitEnter EXIT

main "$@"
