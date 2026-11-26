#!/usr/bin/env bash
# quota-guard2-selftest.sh — 纯函数级自检，不碰真实账号、不发任何请求
# 用法：
#   bash scripts/quota-guard2-selftest.sh [守护脚本路径]
# 默认测试 /usr/local/bin/claude-quota-guard2
set -uo pipefail

GUARD="${1:-/usr/local/bin/claude-quota-guard2}"
[ -r "$GUARD" ] || { echo "找不到守护脚本：$GUARD"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/data"

# 只截取到 one_round 之前（函数定义部分），避免触发主循环
CUT=$(( $(grep -n '^one_round()' "$GUARD" | head -1 | cut -d: -f1) - 1 ))
[ "$CUT" -gt 10 ] || { echo "脚本结构不符合预期，无法自检"; exit 2; }
head -n "$CUT" "$GUARD" > "$TMP/lib.sh"
# 把真实路径换成临时目录，避免在被测机器上创建 /root/.claude
sed -i "s#/root/.claude/failover#$TMP/data#g; s#/root/.claude/tokens#$TMP/tokens#g" "$TMP/lib.sh"

# shellcheck disable=SC1090
. "$TMP/lib.sh"

# —— 桩：probe 从文件读，accounts 固定两个号，log 静音 ——
probe(){ cat "$TMP/data/$1" 2>/dev/null || echo "000 0 0 0 0"; }
accounts(){ echo "alpha beta"; }
log(){ :; }

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n     期望 [%s] 实际 [%s]\n' "$1" "$2" "$3"; }
eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "$2" "$3"; }

echo "== 1. 地板换算 =="
eq "pct(0.87) 周剩余 = 13%" "13" "$(pct 0.87)"
eq "pct(0.98) 周剩余 = 2%"  "2"  "$(pct 0.98)"
eq "wf_of(13) 利用率阈值 = 0.8700" "0.8700" "$(wf_of 13)"
eq "wf_of(8)  利用率阈值 = 0.9200" "0.9200" "$(wf_of 8)"

echo "== 2. 候选筛选（find_best） =="
wf="$(wf_of 13)"

# alpha 周剩 44%、5h 1%；beta 周剩 2%（低于地板）
printf '200 0.01 0.56 0 0\n' > "$TMP/data/alpha"
printf '200 0.10 0.98 0 0\n' > "$TMP/data/beta"
eq "周额度不足的 beta 被排除，选 alpha" "alpha $(awk 'BEGIN{printf "%.6f",0.56*10+0.01}')" "$(find_best cur "$wf" week)"

# 两个都低于地板 → 无候选
printf '200 0.10 0.98 0 0\n' > "$TMP/data/alpha"
eq "两个号都触地板 → 无候选" "" "$(find_best cur "$wf" week)"

# beta 周额度够，但 5h 榨干（>=0.95）→ 排除
printf '200 0.10 0.98 0 0\n' > "$TMP/data/alpha"
printf '200 0.97 0.30 0 0\n' > "$TMP/data/beta"
eq "5h 榨干的 beta 被排除" "" "$(find_best cur "$wf" week)"

# 两个都可用时，week 模式优先周余量大的
printf '200 0.10 0.50 0 0\n' > "$TMP/data/alpha"    # 周剩 50%
printf '200 0.01 0.70 0 0\n' > "$TMP/data/beta"     # 周剩 30%
eq "week 模式优先周余量大的 alpha" "alpha $(awk 'BEGIN{printf "%.6f",0.50*10+0.10}')" "$(find_best cur "$wf" week)"

echo "== 3. 等待目标（find_wait_target） =="
NOW="$(date +%s)"
R7_EARLY=$(( NOW + 3600 ))
R7_LATE=$(( NOW + 86400 ))
R5_SOON=$(( NOW + 600 ))

# 周耗尽：alpha 2%（重置 +1h），beta 1%（重置 +24h）→ 选 alpha
printf "200 0.90 0.98 $NOW $R7_EARLY\n" > "$TMP/data/alpha"
printf "200 0.90 0.99 $NOW $R7_LATE\n"  > "$TMP/data/beta"
eq "周耗尽时选最早周重置的 alpha" "alpha $R7_EARLY" "$(find_wait_target week "$wf")"

# 5h 耗尽：两个号周额度都够，beta 5h 更快重置 → 选 beta
printf "200 0.97 0.40 $R5_SOON $R7_LATE\n" > "$TMP/data/alpha"
printf "200 0.97 0.40 $(( NOW + 1200 )) $R7_LATE\n" > "$TMP/data/beta"
eq "5h 耗尽时选最早 5h 重置的 alpha" "alpha $R5_SOON" "$(find_wait_target 5h "$wf")"

# 没有未来重置时间 → 空
printf "200 0.97 0.40 0 0\n" > "$TMP/data/alpha"
printf "200 0.97 0.40 0 0\n" > "$TMP/data/beta"
eq "reset 时间为 0 时不返回目标" "" "$(find_wait_target 5h "$wf")"

echo
printf '结果：%d 通过 / %d 失败\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
