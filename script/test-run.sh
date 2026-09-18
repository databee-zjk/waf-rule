#!/usr/bin/env bash
#
# ============================================================================
# test-run.sh — 実環境での通し試験（1手順ずつ止まって確認できる）
# ============================================================================
#
# 【用途】
#   テスト用の IPSet に対して「空 → 書き込み → 照合 → 空」を一周する。
#   1手順ごとに止まり、AWSコンソールで目視確認するためのURLを表示する。
#   Enter を押すと次の手順へ進む。
#
# 【用法】
#   ./test-run.sh           A と B の両方（1手順ずつ止まる）
#   ./test-run.sh A         パターンAだけ（ALB × IPv4）
#   ./test-run.sh B         パターンBだけ（CloudFront × IPv6）
#   ./test-run.sh --read    読み取りだけ（AWSに一切書き込まない）
#   ./test-run.sh --auto    止まらずに最後まで流す
#
#   組み合わせも可: ./test-run.sh A --auto
#
# 【個別に確認したい場合】
#   本スクリプトを流さず、下記を1行ずつ実行しても同じことができます。
#   $ARN_A / $ARN_B は下の設定に書いた ARN に読み替えてください。
#   （$GET_A = ./get-bing-ip.sh 、$GET_B = ./get-google-ip.sh --ipv6）
#
#   なお本スクリプトは、書き込みの後に「反映されるまで待つ」処理を挟んでいます。
#   手で実行する場合、書き込み直後（4・7・13・16 の直後）は
#   まだ古い内容が返ることがあります。数秒おいてから確認してください。
#   （AWS WAF の IPSet 更新は結果整合性のため）
#
#   --- パターンA: ALB（リージョン） × IPv4 ---
#    1) ./waf-ipset.sh list  --arn=$ARN_A
#    2) ./waf-ipset.sh clear --arn=$ARN_A --apply
#    3) ./waf-ipset.sh list  --arn=$ARN_A
#    4) ./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=$ARN_A --apply
#    5) ./waf-ipset.sh list  --arn=$ARN_A
#    6) ./get-bing-ip.sh 2>/dev/null | sort > expect-a.txt && \
#       ./waf-ipset.sh list --arn=$ARN_A --pipe 2>/dev/null | sort > actual-a.txt && \
#       diff expect-a.txt actual-a.txt && echo '★ 完全一致'
#    7) ./get-bing-ip.sh | ./waf-ipset.sh replace -f - --arn=$ARN_A --apply
#       （2回目なので「変更はありません」＋終了コード3 になれば正しい）
#    8) ./waf-ipset.sh clear --arn=$ARN_A --apply
#    9) ./waf-ipset.sh list  --arn=$ARN_A
#
#   --- パターンB: CloudFront（グローバル） × IPv6 ---
#   10) ./waf-ipset.sh list  --arn=$ARN_B
#   11) ./waf-ipset.sh clear --arn=$ARN_B --apply
#   12) ./waf-ipset.sh list  --arn=$ARN_B
#   13) ./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=$ARN_B --apply
#   14) ./waf-ipset.sh list  --arn=$ARN_B
#   15) ./get-google-ip.sh --ipv6 2>/dev/null | sort > expect-b.txt && \
#       ./waf-ipset.sh list --arn=$ARN_B --pipe 2>/dev/null | sort > actual-b.txt && \
#       diff expect-b.txt actual-b.txt && echo '★ 完全一致'
#   16) ./get-google-ip.sh --ipv6 | ./waf-ipset.sh replace -f - --arn=$ARN_B --apply
#       （2回目なので「変更はありません」＋終了コード3 になれば正しい）
#   17) ./waf-ipset.sh clear --arn=$ARN_B --apply
#   18) ./waf-ipset.sh list  --arn=$ARN_B
#
#   6 と 15（照合）が通れば、本番適用の判断材料としては十分です。
#   最後に後片付け: rm -f expect-a.txt actual-a.txt expect-b.txt actual-b.txt
#
# 【何をするか】
#   下の設定に書いた「テスト用 IPSet」の中身を書き換えます。
#   本番の IPSet を指定しないこと。
#
# 【出参】
#   画面: 手順ごとに「実行したコマンド」「結果」「判定」「確認用URL」
#   終了コード: 0=全て期待どおり / 1=期待と違うものがあった / 2=引数エラー
#
# 【実行環境】
#   Git Bash（Windows）/ bash 4.4 以上。aws CLI v2 と認証情報が必要。
#
# 【費用】
#   AWS WAF の get-ip-set / update-ip-set のみ。$0（課金対象外）。
#
# [zjk 2026-09-18 AI補助]
# ============================================================================

set -u

# ---- 本スクリプトの設定（改这里）------------------------------------------

# パターンA で使うテスト用 IPSet（ALB＝リージョン、IPv4）
ARN_A="arn:aws:wafv2:ap-northeast-1:807201113290:regional/ipset/ZhangJiekun-TEST-IPv4/89c88085-ddae-4a99-b7d8-e31c23db2ce8"

# パターンB で使うテスト用 IPSet（CloudFront＝グローバル、IPv6）
ARN_B="arn:aws:wafv2:us-east-1:807201113290:global/ipset/ZhangJiekun-TEST-IPv6/ee1b0654-928f-4641-a7d1-95cca83e4fe1"

# パターンA で書き込むIPの取得元。
# Bing は28件と少なく、2年以上内容が変わっていないため照合しやすい。
GET_A="./get-bing-ip.sh"

# パターンB で書き込むIPの取得元。IPv6 を公開しているのは実質 Google のみ。
GET_B="./get-google-ip.sh --ipv6"

# 書き込み後、反映されるまで待つ上限（秒）。
# AWS WAF の IPSet 更新は結果整合性で、通常は数秒で反映される。
# 混雑時は分単位になることもあるため、待てるなら大きくしてよい。
WAIT_LIMIT=90

# 反映を確認する間隔（秒）。短くすると反応は速いが、その分APIを多く呼ぶ。
WAIT_INTERVAL=5

# ---- 設定ここまで ----------------------------------------------------------

cd "$(dirname "$0")" || exit 1
export NO_PAUSE=1

OK_COUNT=0
NG_COUNT=0
MODE="ALL"
AUTO=0

# NG になった手順と、その場で示した原因を貯めておく（最後にまとめて出す）
declare -a NG_LIST=()


# ============================================================================
# main — 全体の流れ
# ============================================================================
main() {
    func_parseArgs "$@"
    func_printHeader

    case "$MODE" in
        A)      func_patternA ;;
        B)      func_patternB ;;
        READ)   func_readOnly ;;
        ALL)    func_patternA; func_patternB ;;
    esac

    func_printSummary
}


# ============================================================================
# 引数
# ============================================================================

# func_parseArgs
#   入参: コマンドライン引数すべて
#   出参: MODE / AUTO を設定
func_parseArgs() {
    while [ $# -gt 0 ]; do
        case "$1" in
            A|a)     MODE="A" ; shift ;;
            B|b)     MODE="B" ; shift ;;
            --read)  MODE="READ" ; shift ;;
            --auto)  AUTO=1 ; shift ;;
            -h|--help)
                echo "使い方: ./test-run.sh [A|B|--read] [--auto]"
                echo "  A        ALB × IPv4 のみ"
                echo "  B        CloudFront × IPv6 のみ"
                echo "  --read   読み取りだけ（書き込まない）"
                echo "  --auto   1手順ごとに止まらず最後まで流す"
                exit 0
                ;;
            *)
                echo "不明な引数: $1" >&2
                echo "使い方: ./test-run.sh [A|B|--read] [--auto]" >&2
                exit 2
                ;;
        esac
    done

    # 対話できない環境（cron・パイプ・リダイレクト）では止まらない。
    # ここを外すと cron で永久に待ち続けてプロセスが残る。
    if [ ! -r /dev/tty ] || [ ! -t 1 ]; then
        AUTO=1
    fi
}


# ============================================================================
# ARN からコンソールURLを組み立てる
# ============================================================================

# func_consoleUrl
#   入参: $1=IPSet の ARN
#   出参: その IPSet の個別ページを直接開くURLを標準出力
#   備考: 新コンソール（wafv2-pro）の直リンク形式。
#         /wafv2-pro/ip-sets/{名前}/{ID}?region={リージョン}&scope={スコープ}
#         名前・ID・スコープは ARN の末尾がそのまま使える。
#         （旧形式 /wafv2/homev2/ip-set/... は 404 になる）
#         CloudFront（global）の IPSet は ARN 上 us-east-1 配下。
#         どの IPSet を開くかを決めるのは scope で、host/region は入口でしかない。
func_consoleUrl() {
    local arn="$1"
    local a_arn a_part a_svc a_region a_acct a_rest
    IFS=':' read -r a_arn a_part a_svc a_region a_acct a_rest <<< "$arn"

    local a_scope a_kind a_name a_id
    IFS='/' read -r a_scope a_kind a_name a_id <<< "$a_rest"

    echo "https://${a_region}.console.aws.amazon.com/wafv2-pro/ip-sets/${a_name}/${a_id}?region=${a_region}&scope=${a_scope}"
}

# func_ipSetName
#   入参: $1=IPSet の ARN
#   出参: IPSet 名を標準出力
func_ipSetName() {
    local arn="$1" a_rest a_scope a_kind a_name a_id
    a_rest="${arn##*:}"
    IFS='/' read -r a_scope a_kind a_name a_id <<< "$a_rest"
    echo "$a_name"
}


# ============================================================================
# 画面表示
# ============================================================================

# func_printHeader
#   入参: なし / 出参: これから何をするかを表示
func_printHeader() {
    echo
    echo "############################################################"
    echo "# WAF IPSet 通し試験"
    echo "############################################################"
    echo "# 実行日時 : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# モード   : $MODE$([ "$AUTO" -eq 1 ] && echo "（自動・止まりません）")"
    echo "#"

    if [ "$MODE" = "ALL" ] || [ "$MODE" = "A" ] || [ "$MODE" = "READ" ]; then
        echo "# A) $(func_ipSetName "$ARN_A")  （ALB / リージョン / IPv4）"
        echo "#    $(func_consoleUrl "$ARN_A")"
    fi
    if [ "$MODE" = "ALL" ] || [ "$MODE" = "B" ] || [ "$MODE" = "READ" ]; then
        echo "# B) $(func_ipSetName "$ARN_B")  （CloudFront / グローバル / IPv6）"
        echo "#    $(func_consoleUrl "$ARN_B")"
    fi

    echo "#"
    echo "# 各手順の「\$ ...」の行が実際のコマンドです。"
    echo "# 個別に試したい場合はその行をコピペしてください。"
    echo "############################################################"

    if [ "$AUTO" -eq 0 ]; then
        echo
        local ans=""
        read -r -p " Enter で開始します（q で中断）> " ans < /dev/tty
        [ "$ans" = "q" ] && { echo " 中断しました。"; exit 0; }
    fi
}

# func_step
#   入参: $1=手順名, $2=期待する終了コード, $3=実行するコマンド,
#         $4=コンソールで確認する内容（空なら確認を促さない）, $5=確認対象のARN（省略可）
#   出参: コマンドを表示して実行し、判定と確認用URLを出す
#   備考: パイプを含むコマンドをそのまま表示・実行するため eval を使っている。
func_step() {
    local title="$1" expect="$2" cmd="$3" check="${4:-}" arn="${5:-}" hint="${6:-}"

    echo
    echo "------------------------------------------------------------"
    echo " $title"
    echo "------------------------------------------------------------"
    echo "\$ $cmd"
    echo "  - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

    eval "$cmd"
    local code=$?

    echo "  - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    if [ "$code" = "$expect" ]; then
        echo " [ OK ] 終了コード $code（期待どおり）"
        OK_COUNT=$((OK_COUNT + 1))
    else
        echo " [ NG ] 終了コード $code（期待は $expect）"
        NG_COUNT=$((NG_COUNT + 1))
        # NG を見た人がその場で原因を判断できるようにする。
        # 「NGが出た → 何が悪いのか分からない」という状態を作らない。
        if [ -n "$hint" ]; then
            echo
            echo " ┌─ この NG について ─────────────────────────"
            # hint は | 区切りの複数行。単語分割されないよう1行ずつ読む。
            echo "$hint" | tr '|' '\n' | while IFS= read -r line; do
                echo " │ $line"
            done
            echo " └────────────────────────────────────────────"
        fi
        NG_LIST+=("${title%%.*}. ${hint%%|*}")
    fi

    func_pause "$check" "$arn"
}

# func_stepEither
#   入参: $1=手順名, $2=期待コード1, $3=期待コード2, $4=コマンド,
#         $5=確認内容, $6=確認対象のARN
#   出参: func_step と同じ
#   備考: clear は「空にした(0)」「元々空(3)」のどちらも正常なため2つ許容する。
func_stepEither() {
    local title="$1" e1="$2" e2="$3" cmd="$4" check="${5:-}" arn="${6:-}"

    echo
    echo "------------------------------------------------------------"
    echo " $title"
    echo "------------------------------------------------------------"
    echo "\$ $cmd"
    echo "  - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

    eval "$cmd"
    local code=$?

    echo "  - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    if [ "$code" = "$e1" ] || [ "$code" = "$e2" ]; then
        echo " [ OK ] 終了コード $code（期待は $e1 または $e2）"
        OK_COUNT=$((OK_COUNT + 1))
    else
        echo " [ NG ] 終了コード $code（期待は $e1 または $e2）"
        NG_COUNT=$((NG_COUNT + 1))
    fi

    func_pause "$check" "$arn"
}

# func_pause
#   入参: $1=コンソールで確認する内容（空なら表示しない）, $2=対象のARN（省略可）
#   出参: なし。Enter 待ちをする（--auto 指定時は待たない）
#   備考: 標準入力がパイプで塞がれていても操作できるよう /dev/tty から読む。
func_pause() {
    local check="${1:-}" arn="${2:-}"

    if [ -n "$check" ]; then
        echo
        echo " ★ コンソールで確認: $check"
        if [ -n "$arn" ]; then
            echo "   $(func_ipSetName "$arn") : $(func_consoleUrl "$arn")"
        fi
    fi

    [ "$AUTO" -eq 1 ] && return

    echo
    local ans=""
    read -r -p " Enter で次へ／s でスキップ／q で中断 > " ans < /dev/tty
    case "$ans" in
        q|Q) echo " 中断しました。"; func_printSummary ;;
        s|S) echo " （この先の確認を省略して自動で流します）"; AUTO=1 ;;
    esac
}

# func_waitPropagation
#   入参: $1=手順名, $2=ARN, $3=期待する件数
#   出参: 件数が一致するまで待つ。判定して OK_COUNT / NG_COUNT を更新
#   備考: AWS WAF の IPSet 更新は「結果整合性」で、書き込み直後に読むと
#         古い内容が返ることがある（数秒〜数分で伝播）。
#         固定で sleep すると速い時に無駄になるため、一致するまで繰り返し読む。
#         これを入れないと「書いたのに反映されていない」ように見えて
#         照合と冪等性の確認が落ちる。
func_waitPropagation() {
    local title="$1" arn="$2" want="$3"
    local waited=0 now=0

    echo
    echo "------------------------------------------------------------"
    echo " $title"
    echo "------------------------------------------------------------"
    echo " AWS WAF の更新は反映まで数秒かかります（結果整合性）。"
    echo " 件数が $want 件になるまで待ちます..."
    echo "  - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

    while [ "$waited" -lt "$WAIT_LIMIT" ]; do
        now=$(./waf-ipset.sh list --arn="$arn" --pipe 2>/dev/null | grep -c . || true)
        if [ "$now" = "$want" ]; then
            echo "  - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
            echo " [ OK ] ${waited}秒で反映されました（$now 件）"
            OK_COUNT=$((OK_COUNT + 1))
            return 0
        fi
        printf '  %2d秒: %s 件（期待 %s 件）\n' "$waited" "$now" "$want"
        sleep "$WAIT_INTERVAL"
        waited=$((waited + WAIT_INTERVAL))
    done

    echo "  - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    echo " [ NG ] ${WAIT_LIMIT}秒待っても一致しません（現在 $now 件 / 期待 $want 件）"
    echo "        AWS側の伝播が遅れているだけの可能性があります。"
    echo "        少し待ってから list で確認してください。"
    NG_COUNT=$((NG_COUNT + 1))
    return 1
}

# func_printSummary
#   入参: なし / 出参: 集計を表示して終了する
func_printSummary() {
    echo
    echo "############################################################"
    echo "# 結果: OK $OK_COUNT 件 / NG $NG_COUNT 件"
    echo "############################################################"

    if [ "$NG_COUNT" -eq 0 ]; then
        echo "# 全て期待どおりです。"
        echo "############################################################"
        echo
        exit 0
    fi

    echo "#"
    echo "# NG の内訳と原因:"
    local item
    for item in "${NG_LIST[@]}"; do
        echo "#   $item"
    done
    echo "#"
    echo "# 詳しい説明は、各手順の「この NG について」の枠内に出ています。"
    echo "############################################################"
    echo
    exit 1
}


# ============================================================================
# パターンA: ALB（リージョン） × IPv4
# ============================================================================
func_patternA() {
    echo
    echo "============================================================"
    echo "== パターンA: ALB（リージョン） × IPv4"
    echo "== 対象: $(func_ipSetName "$ARN_A")"
    echo "============================================================"

    func_step "A-1. 現在の内容を見る（接続・権限・ARNの確認）" 0 \
        "./waf-ipset.sh list --arn=$ARN_A" \
        "コンソールの一覧と、画面に出た内容が同じこと" "$ARN_A"

    func_stepEither "A-2. いったん空にする" 0 3 \
        "./waf-ipset.sh clear --arn=$ARN_A --apply" \
        "" ""

    func_waitPropagation "A-3. 空になるまで待つ" "$ARN_A" 0

    func_step "A-4. 空になったことを確認" 0 \
        "./waf-ipset.sh list --arn=$ARN_A" \
        "コンソールの IP addresses が空になっていること" "$ARN_A"

    # 書き込む件数を先に数えておく（反映待ちの判定に使う）
    local want_a
    want_a=$($GET_A 2>/dev/null | grep -c .)

    func_step "A-5. Bing のIPを書き込む（${want_a}件）" 0 \
        "$GET_A | ./waf-ipset.sh replace -f - --arn=$ARN_A --apply" \
        "" ""

    func_waitPropagation "A-6. 反映されるまで待つ" "$ARN_A" "$want_a"

    func_step "A-7. 入ったことを確認" 0 \
        "./waf-ipset.sh list --arn=$ARN_A" \
        "コンソールに${want_a}件のIPが並んでいること（ページを再読み込み）" "$ARN_A"

    func_step "A-8. 取得元と1件単位で照合（★本番の判断材料）" 0 \
        "$GET_A 2>/dev/null | sort > expect-a.txt && ./waf-ipset.sh list --arn=$ARN_A --pipe 2>/dev/null | sort > actual-a.txt && diff expect-a.txt actual-a.txt && echo '★ 完全一致（差分ゼロ）'" \
        "" "" \
        "反映待ちが足りないか、取得元が更新された可能性|上の diff が「<」だけ、または「>」だけに偏っている場合は反映待ち不足です。|WAIT_LIMIT を増やして再実行してください。|Google は毎日更新されるため、実行中に取得元が変わることも稀にあります。"

    func_step "A-9. もう一度流して、書き込まないことを確認（冪等性）" 3 \
        "$GET_A | ./waf-ipset.sh replace -f - --arn=$ARN_A --apply" \
        "コンソールの内容が A-7 から変わっていないこと" "$ARN_A" \
        "A-8 が NG なら、これも連鎖して NG になります|内容が違うと「変化あり」と判定され、書き込みが走るためです。|A-8 が OK なのにこれだけ NG の場合は、反映待ち（A-6）が足りていません。"

    func_step "A-10. 空に戻す" 0 \
        "./waf-ipset.sh clear --arn=$ARN_A --apply" \
        "" ""

    func_waitPropagation "A-11. 空になるまで待つ" "$ARN_A" 0

    func_step "A-12. 空になったことを確認" 0 \
        "./waf-ipset.sh list --arn=$ARN_A" \
        "コンソールの IP addresses が空に戻っていること" "$ARN_A"

    rm -f expect-a.txt actual-a.txt
}


# ============================================================================
# パターンB: CloudFront（グローバル） × IPv6
# ============================================================================
func_patternB() {
    echo
    echo "============================================================"
    echo "== パターンB: CloudFront（グローバル） × IPv6"
    echo "== 対象: $(func_ipSetName "$ARN_B")"
    echo "============================================================"

    func_step "B-1. 現在の内容を見る（CLOUDFRONT / us-east-1 と出るはず）" 0 \
        "./waf-ipset.sh list --arn=$ARN_B" \
        "コンソール右上のリージョンが Global (CloudFront) になっていること" "$ARN_B"

    func_stepEither "B-2. いったん空にする" 0 3 \
        "./waf-ipset.sh clear --arn=$ARN_B --apply" \
        "" ""

    func_waitPropagation "B-3. 空になるまで待つ" "$ARN_B" 0

    func_step "B-4. 空になったことを確認" 0 \
        "./waf-ipset.sh list --arn=$ARN_B" \
        "コンソールの IP addresses が空になっていること" "$ARN_B"

    # 書き込む件数を先に数えておく（反映待ちの判定に使う）
    local want_b
    want_b=$($GET_B 2>/dev/null | grep -c .)

    func_step "B-5. Google の IPv6 を書き込む（${want_b}件）" 0 \
        "$GET_B | ./waf-ipset.sh replace -f - --arn=$ARN_B --apply" \
        "" ""

    func_waitPropagation "B-6. 反映されるまで待つ" "$ARN_B" "$want_b"

    func_step "B-7. 入ったことを確認" 0 \
        "./waf-ipset.sh list --arn=$ARN_B" \
        "コンソールに${want_b}件のIPv6が並んでいること（ページを再読み込み）" "$ARN_B"

    func_step "B-8. 取得元と1件単位で照合（★本番の判断材料）" 0 \
        "$GET_B 2>/dev/null | sort > expect-b.txt && ./waf-ipset.sh list --arn=$ARN_B --pipe 2>/dev/null | sort > actual-b.txt && diff expect-b.txt actual-b.txt && echo '★ 完全一致（差分ゼロ）'" \
        "" "" \
        "IPv6の表記差の可能性（機能の不具合ではない）|上の diff で「<」と「>」が同じアドレスの別表記になっていないか見てください。|IPv6は同じアドレスに複数の書き方があり（例: 2001:4860:c::10/124 と|2001:4860:000c:0000:0000:0000:0000:0010/124）、AWS側が正規化して保存することがあります。|その場合、中身は正しく入っています。件数（B-6）が合っていればなおさらです。|別のアドレスが出ている・件数が違う場合は、本当の不一致です。"

    func_step "B-9. もう一度流して、書き込まないことを確認（冪等性）" 3 \
        "$GET_B | ./waf-ipset.sh replace -f - --arn=$ARN_B --apply" \
        "コンソールの内容が B-7 から変わっていないこと" "$ARN_B" \
        "B-8 が NG なら、これも連鎖して NG になります|表記が違うと「変化あり」と判定され、毎回書き込みが走るためです。|B-8 が OK なのにこれだけ NG の場合は、反映待ち（B-6）が|足りていない可能性があります。WAIT_LIMIT を増やして再実行してください。"

    func_step "B-10. 空に戻す" 0 \
        "./waf-ipset.sh clear --arn=$ARN_B --apply" \
        "" ""

    func_waitPropagation "B-11. 空になるまで待つ" "$ARN_B" 0

    func_step "B-12. 空になったことを確認" 0 \
        "./waf-ipset.sh list --arn=$ARN_B" \
        "コンソールの IP addresses が空に戻っていること" "$ARN_B"

    rm -f expect-b.txt actual-b.txt
}


# ============================================================================
# 読み取りだけ（書き込みを一切しない）
# ============================================================================
func_readOnly() {
    echo
    echo "============================================================"
    echo "== 読み取りのみ（AWSへの書き込みは一切しません）"
    echo "============================================================"

    func_step "R-1. ALB×IPv4 の内容を見る" 0 \
        "./waf-ipset.sh list --arn=$ARN_A" \
        "コンソールの内容と一致していること" "$ARN_A"

    func_step "R-2. CloudFront×IPv6 の内容を見る" 0 \
        "./waf-ipset.sh list --arn=$ARN_B" \
        "コンソールの内容と一致していること" "$ARN_B"

    func_step "R-3. Bing のIPを取得する（AWSに触れない）" 0 \
        "$GET_A" "" ""

    func_step "R-4. Google の IPv6 を取得する（AWSに触れない）" 0 \
        "$GET_B" "" ""

    func_step "R-5. 書き込まずに差分だけ見る（模擬実行）" 0 \
        "$GET_A | ./waf-ipset.sh replace -f - --arn=$ARN_A" \
        "コンソールの内容が変わっていないこと（模擬実行なので変わらない）" "$ARN_A"
}


main "$@"
