#!/bin/bash
# claude-quota-guard2 — 多账号 / 多会话额度守护 (2026-11-26, rev3)
#
# 周额度地板（核心规则）：
#   - 地板默认 13%：周额度剩余进入 8~13% 区间即停用该号，不管 5h 多空
#   - 可用 WEEK_FLOOR_PCT=8~13 覆盖（调低=更激进，允许用到区间下沿）
#   - 日志跟随服务器本地时区（不写死 +08:00）
#   - 地板值持久化到 $DIR/guard2.floor，重启不重抽，避免阈值来回抖动
#   - 命中地板：立即切换（不受 30 分钟驻留限制）
#   - 没有可用账号：等最近的恢复点（周重置 r7，或另一号 5h 重置 r5，取更早者）
#     到点后复核通过才切；周重置 +30~60 分钟随机，5h 重置 +10~30 分钟随机
#
# 5h 触发：每轮抽 X = 10~20，5h 利用率 >= 1-X% 时换到更闲的号（遵守 30 分钟驻留）
# 候选条件：http=200 且 周剩余 > 地板% 且 5h < 95%
# 续跑：只给未完成会话发「继续」，串行，间隔 5-10 秒随机
# 重启会话保留原 --model / --effort / --permission-mode
#
# 测试接缝（生产不用）：
#   TOK_DIR / STATE_DIR 可换目录；PROBE_STUB 可替换探测；DRY_RUN=1 只记录不动作；--once 只跑一轮
set -uo pipefail

TOK="${TOK_DIR:-/root/.claude/tokens}"
DIR="${STATE_DIR:-/root/.claude/failover}"
ACTIVE="$TOK/active"
LOG="$DIR/guard2.log"
STATE="$DIR/guard2.state"
WAITF="$DIR/guard2.wait"
FLOORF="$DIR/guard2.floor"
LOCK="$DIR/guard2.lock"

DWELL=1800
WAIT_MIN=1800
WAIT_MAX=3600
WAIT5_MIN=600
WAIT5_MAX=1800
H5_MAX=0.95
X_MIN=10
X_MAX=20
DRY="${DRY_RUN:-0}"
MAX_ITERS=0
ITERS=0
INTERVAL=600
FLOOR=13

mkdir -p "$DIR"

log(){ echo "$(TZ=America/Los_Angeles date '+%F %T') $*" >> "$LOG"; [ "$DRY" = "1" ] && echo "$(TZ=America/Los_Angeles date '+%H:%M:%S') $*" >&2; }

rotate_log(){
  local sz
  sz="$(stat -c%s "$LOG" 2>/dev/null || echo 0)"
  if [ "${sz:-0}" -gt 4194304 ]; then mv -f "$LOG" "$LOG.1" 2>/dev/null || true; fi
}

probe(){
  local f="$TOK/$1.env" hdr code u5 u7 r5 r7 ln first
  u5=""; u7=""; r5=""; r7=""; code=""
  if [ -n "${PROBE_STUB:-}" ]; then "$PROBE_STUB" "$1"; return; fi
  [ -r "$f" ] || { echo "000 0 0 0 0"; return; }
  hdr="$(curl -s -D - -o /dev/null --max-time 40 https://api.anthropic.com/v1/messages \
    -H "Authorization: Bearer $(cat "$f")" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "content-type: application/json" \
    -d '{"model":"claude-haiku-4-5","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' 2>/dev/null)"
  IFS= read -r first <<< "$hdr"
  first="${first%$'\r'}"
  code="${first#* }"; code="${code%% *}"
  case "$code" in ''|*[!0-9]*) code=000 ;; esac
  while IFS= read -r ln; do
    ln="${ln%$'\r'}"
    case "${ln,,}" in
      anthropic-ratelimit-unified-5h-utilization:*) u5="${ln#*: }" ;;
      anthropic-ratelimit-unified-7d-utilization:*) u7="${ln#*: }" ;;
      anthropic-ratelimit-unified-5h-reset:*)        r5="${ln#*: }" ;;
      anthropic-ratelimit-unified-7d-reset:*)        r7="${ln#*: }" ;;
    esac
  done <<< "$hdr"
  echo "${code:-000} ${u5:-0} ${u7:-0} ${r5:-0} ${r7:-0}"
}

mx(){ awk -v a="$1" -v b="$2" 'BEGIN{printf "%.4f", (a>b?a:b)}'; }
ge(){ awk -v u="$1" -v t="$2" 'BEGIN{exit !(u+0>=t+0)}'; }
lt(){ awk -v u="$1" -v t="$2" 'BEGIN{exit !(u+0<t+0)}'; }
pct(){ awk -v u="$1" 'BEGIN{printf "%d", (1-u)*100+0.5}'; }
wf_of(){ awk -v w="$1" 'BEGIN{printf "%.4f", 1-w/100}'; }

accounts(){ for f in "$TOK"/*.env; do [ -r "$f" ] && basename "$f" .env; done; }
cur_acct(){ [ -L "$ACTIVE" ] && basename "$(readlink -f "$ACTIVE")" .env; }
sessions(){ tmux ls -F '#{session_name}' 2>/dev/null; }

pane_busy(){ tmux capture-pane -p -t "$1" 2>/dev/null | tail -8 | grep -q "esc to interrupt"; }
pane_has_limit(){ tmux capture-pane -p -t "$1" -S -40 2>/dev/null | grep -v 'Context limit' | grep -qiE 'usage limit reached|limit reached|rate_limit_error|API Error: 429'; }

# 只取该 pane 的后代进程，避免抓到别的会话
descendants(){
  local root="$1" out="" cur c
  local queue=("$root")
  while [ ${#queue[@]} -gt 0 ]; do
    cur="${queue[0]}"; queue=("${queue[@]:1}")
    for c in $(pgrep -P "$cur" 2>/dev/null); do out="$out $c"; queue+=("$c"); done
  done
  printf '%s' "$out"
}

pane_claude_args(){
  local s="$1" pid p cmd
  pid="$(tmux list-panes -t "$s" -F '#{pane_pid}' 2>/dev/null | head -1)"
  [ -z "$pid" ] && return
  for p in $(descendants "$pid"); do
    cmd="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)"
    case "$cmd" in
      *"/claude "|*"/claude"|claude\ *) printf '%s' "$cmd"; return ;;
    esac
  done
}

norm_args(){
  local raw=" $1 " m e pm out="-c"
  m="$(printf '%s' "$raw" | grep -oE -- '--model[ =][^ ]+' | head -1 | sed -E 's/--model[ =]//')"
  e="$(printf '%s' "$raw" | grep -oE -- '--effort[ =][^ ]+' | head -1 | sed -E 's/--effort[ =]//')"
  pm="$(printf '%s' "$raw" | grep -oE -- '--permission-mode[ =][^ ]+' | head -1 | sed -E 's/--permission-mode[ =]//')"
  out="$out --model ${m:-opus} --effort ${e:-max}"
  [ -n "$pm" ] && out="$out --permission-mode $pm"
  printf '%s' "$out"
}

switch_to(){
  local target="$1" reason="$2" cur; cur="$(cur_acct)"
  log "SWITCH $cur -> $target ($reason)"
  if [ "$DRY" = "1" ]; then log "[dry] would relink active -> $target"; return 0; fi

  ln -sfn "$TOK/$target.env" "$ACTIVE" || { log "relink failed"; return 1; }
  local s cwd raw args busy
  for s in $(sessions); do
    raw="$(pane_claude_args "$s")"
    if [ -z "$raw" ]; then log "  skip $s (no claude process)"; continue; fi
    busy=0; pane_busy "$s" && busy=1
    cwd="$(tmux display-message -p -t "$s" '#{pane_current_path}' 2>/dev/null)"
    args="$(norm_args "$raw")"
    tmux kill-session -t "$s" 2>/dev/null
    sleep 3
    tmux new-session -d -s "$s" -c "${cwd:-/root}" "IS_SANDBOX=1 claude-safe $args; exec bash -l"
    log "  restarted $s args=[$args] busy=$busy"
    sleep 12
    if [ "$busy" = "1" ] || pane_has_limit "$s"; then
      tmux send-keys -t "$s" -l "继续"; sleep 1; tmux send-keys -t "$s" Enter
      log "  sent 继续 -> $s"
    fi
    sleep $(( RANDOM % 6 + 5 ))
  done
  date +%s > "$STATE"
  rm -f "$WAITF"
  log "switch done"
}

# 选候选：http=200 且 u7 < 地板 且 u5 < 95%
# mode=week 时按周余量优先，mode=5h 时按 5h 余量优先
# 输出: "账号 分数"，没有则空
find_best(){
  local cur="$1" wf="$2" mode="$3" a cc c5 c7 cr5 cr7 score best="" bestscore=""
  for a in $(accounts); do
    [ "$a" = "$cur" ] && continue
    read -r cc c5 c7 cr5 cr7 <<< "$(probe "$a")"
    [ -z "$cc" ] && cc=000
    if [ "$cc" != "200" ]; then log "  cand $a skip: http=$cc"; continue; fi
    if ! lt "${c7:-0}" "$wf"; then log "  cand $a skip: week_left=$(pct "${c7:-0}")%<=floor"; continue; fi
    if ! lt "${c5:-0}" "$H5_MAX"; then log "  cand $a skip: 5h=${c5:-0} exhausted"; continue; fi
    if [ "$mode" = "week" ]; then
      score="$(awk -v a="${c5:-0}" -v b="${c7:-0}" 'BEGIN{printf "%.6f", b*10 + a}')"
    else
      score="$(awk -v a="${c5:-0}" -v b="${c7:-0}" 'BEGIN{printf "%.6f", a*10 + b}')"
    fi
    if [ -z "$best" ] || lt "$score" "$bestscore"; then best="$a"; bestscore="$score"; fi
  done
  [ -n "$best" ] && printf '%s %s' "$best" "$bestscore"
}

# 找最近的未来时间点：$1=kind(week|5h)，$2=地板 wf
# 输出: "账号 时间戳"，没有则空
find_wait_target(){
  local kind="$1" wf="$2" a cc c5 c7 cr5 cr7 t now next=0 ntarget=""
  now="$(date +%s)"
  for a in $(accounts); do
    read -r cc c5 c7 cr5 cr7 <<< "$(probe "$a")"
    [ -z "$cc" ] && cc=000
    [ "$cc" = "200" ] || continue
    if [ "$kind" = "week" ]; then
      lt "${c7:-0}" "$wf" && continue          # 周额度还有余量的号不需要等
      t="${cr7:-0}"
    else
      lt "${c7:-0}" "$wf" || continue          # 5h 阻塞只针对周额度够的号
      ge "${c5:-0}" "$H5_MAX" || continue
      t="${cr5:-0}"
    fi
    [ "${t:-0}" -gt "$now" ] 2>/dev/null || continue
    if [ "$next" = "0" ] || [ "$t" -lt "$next" ]; then next="$t"; ntarget="$a"; fi
  done
  [ -n "$ntarget" ] && printf '%s %s' "$ntarget" "$next"
}

one_round(){
  local W X wf th code u5 u7 r5 r7 cur last age dead wb h5p week_left best bs a
  W="$(( RANDOM % (X_MAX - X_MIN + 1) + X_MIN ))"     # 5h 触发档 10~20
  wf="$(wf_of "$FLOOR")"
  th="$(awk -v x="$W" 'BEGIN{printf "%.4f", 1-x/100}')"
  INTERVAL=$(( W * 60 ))

  cur="$(cur_acct)"
  if [ -z "$cur" ]; then log "no active account symlink; skip"; return; fi
  read -r code u5 u7 r5 r7 <<< "$(probe "$cur")"
  [ -z "$code" ] && code=000
  [ -z "$u5" ] && u5=0
  [ -z "$u7" ] && u7=0

  last="$(cat "$STATE" 2>/dev/null || echo 0)"
  age=$(( $(date +%s) - last ))
  week_left="$(pct "$u7")"
  dead=0;    [ "$code" != "200" ] && dead=1
  wb=0;      ge "$u7" "$wf" && wb=1
  h5p=0;     ge "$u5" "$th" && h5p=1

  log "check cur=$cur http=$code 5h=$u5 7d=$u7 week_left=${week_left}% floor=${FLOOR}% th5h=$th dead=$dead banned_week=$wb h5_hit=$h5p dwell_left=$(( DWELL - age > 0 ? DWELL - age : 0 ))s next=${INTERVAL}s"

  # ---------- 等待阶段 ----------
  if [ -f "$WAITF" ]; then
    local w_target w_until w_kind now nowleft tc t5 t7 tr5 tr7
    read -r w_target w_until w_kind <<< "$(cat "$WAITF")"
    now="$(date +%s)"
    nowleft=$(( ${w_until:-0} - now ))

    if [ "$nowleft" -le 0 ]; then
      read -r tc t5 t7 tr5 tr7 <<< "$(probe "$cur")"
      [ -z "$tc" ] && tc=000
      if [ "$tc" = "200" ] && lt "${t7:-0}" "$wf"; then
        log "wait ended: current $cur recovered (7d=${t7:-0} < floor); cancel wait"
        rm -f "$WAITF"
        return
      fi
      read -r tc t5 t7 tr5 tr7 <<< "$(probe "$w_target")"
      [ -z "$tc" ] && tc=000
      if [ "$w_kind" = "5h" ]; then
        if [ "$tc" = "200" ] && lt "${t7:-0}" "$wf" && lt "${t5:-0}" "$H5_MAX"; then
          switch_to "$w_target" "5h-reset(5h=${t5:-0},7d=${t7:-0})"
        else
          log "5h wait expired but $w_target not usable (http=$tc 5h=${t5:-0} 7d=${t7:-0}); re-evaluate"
          rm -f "$WAITF"
        fi
      else
        if [ "$tc" = "200" ] && lt "${t7:-0}" "$wf"; then
          switch_to "$w_target" "weekly-reset(7d=${t7:-0}<wf)"
        else
          log "weekly wait expired but $w_target not usable (http=$tc 7d=${t7:-0}); re-evaluate"
          rm -f "$WAITF"
        fi
      fi
      return
    fi

    # 还没到点：若当前已解除地板、或出现可用候选，提前结束等待
    if [ "$dead" = "0" ] && [ "$wb" = "0" ]; then
      log "wait cancelled: current $cur no longer week-banned (week_left=${week_left}%)"
      rm -f "$WAITF"
      return
    fi
    best="$(find_best "$cur" "$wf" week)"
    if [ -n "$best" ]; then
      set -- $best
      switch_to "$1" "usable-during-wait"
      return
    fi
    log "waiting $w_kind reset: target=$w_target until=$(TZ=America/Los_Angeles date -d "@$w_until" '+%F %T %Z' 2>/dev/null) (${nowleft}m left)"
    return
  fi

  # ---------- 不需要动作 ----------
  if [ "$dead" = "0" ] && [ "$wb" = "0" ] && [ "$h5p" = "0" ]; then
    return
  fi
  # 仅 5h 压力时遵守驻留；周地板/死号立即处理
  if [ "$dead" = "0" ] && [ "$wb" = "0" ] && [ "$h5p" = "1" ] && [ "$age" -lt "$DWELL" ]; then
    log "5h pressure but dwell not elapsed (${age}<${DWELL}s); hold"
    return
  fi

  # ---------- 选候选 ----------
  local mode=5h
  if [ "$wb" = "1" ] || [ "$dead" = "1" ]; then mode=week; fi
  best="$(find_best "$cur" "$wf" "$mode")"
  if [ -n "$best" ]; then
    set -- $best
    if [ "$dead" = "1" ]; then
      switch_to "$1" "current-http=$code"
    elif [ "$wb" = "1" ]; then
      switch_to "$1" "week_floor:${week_left}%<=${FLOOR}%"
    else
      switch_to "$1" "5h:${u5}>=${th}"
    fi
    return
  fi

  # ---------- 没候选：决定等什么 ----------
  if [ "$dead" = "1" ] || [ "$wb" = "1" ]; then
    local wa="" wt=0 wk="" cand ca ct until
    cand="$(find_wait_target 5h "$wf")"
    if [ -n "$cand" ]; then read -r wa wt <<< "$cand"; wk=5h; fi
    cand="$(find_wait_target week "$wf")"
    if [ -n "$cand" ]; then
      read -r ca ct <<< "$cand"
      if [ -z "$wa" ] || [ "$ct" -lt "$wt" ]; then wa="$ca"; wt="$ct"; wk=week; fi
    fi
    if [ -n "$wa" ]; then
      if [ "$wk" = "5h" ]; then
        until=$(( wt + RANDOM % (WAIT5_MAX - WAIT5_MIN + 1) + WAIT5_MIN ))
        printf '%s %s 5h\n' "$wa" "$until" > "$WAITF"
        log "week floor: other account weekly ok but 5h exhausted; target=$wa 5h_reset=$(TZ=America/Los_Angeles date -d "@$wt" '+%F %T %Z' 2>/dev/null) wait_until=$(TZ=America/Los_Angeles date -d "@$until" '+%F %T %Z' 2>/dev/null)"
      else
        until=$(( wt + RANDOM % (WAIT_MAX - WAIT_MIN + 1) + WAIT_MIN ))
        printf '%s %s week\n' "$wa" "$until" > "$WAITF"
        log "week floor: no usable account; target=$wa weekly_reset=$(TZ=America/Los_Angeles date -d "@$wt" '+%F %T %Z' 2>/dev/null) wait_until=$(TZ=America/Los_Angeles date -d "@$until" '+%F %T %Z' 2>/dev/null)"
      fi
      return
    fi
    log "week floor: no usable account and no future reset found; retry next round"
    return
  fi

  # 仅 5h 压力且无候选：保持当前号，等它自己 5h 重置
  log "5h pressure but no usable candidate; hold current (5h resets at $(TZ=America/Los_Angeles date -d "@$r5" '+%F %T %Z' 2>/dev/null))"
}

# ---------- 参数 ----------
case "${1:-}" in
  --status)
    rotate_log
    printf '%-18s %-6s %-8s %-8s %-10s %s\n' ACCOUNT HTTP 5H 7D WEEK_LEFT RESET_7D
    for a in $(accounts); do
      read -r c u5 u7 r5 r7 <<< "$(probe "$a")"
      [ -z "$c" ] && c=000
      printf '%-18s %-6s %-8s %-8s %-9s %s\n' "$a" "$c" "${u5:-0}" "${u7:-0}" "$(pct "${u7:-0}")%" "$(TZ=America/Los_Angeles date -d "@${r7:-0}" '+%m-%d %H:%M' 2>/dev/null)"
    done
    FL="$(cat "$FLOORF" 2>/dev/null || true)"
    echo "active: $(cur_acct)   周地板: ${FL:-未设置（默认 13）}%   等待中: $([ -f "$WAITF" ] && cat "$WAITF" || echo '无')"
    exit 0
    ;;
  --once)   MAX_ITERS=1 ;;
  --help|-h)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "") ;;
  *) echo "unknown arg: $1 (use --status|--once|--help)" >&2; exit 2 ;;
esac

# ---------- 单实例锁 ----------
exec 9>"$LOCK" || { echo "cannot open lock $LOCK" >&2; exit 1; }
flock -n 9 || { echo "another guard2 instance holds $LOCK" >&2; exit 0; }

# ---------- 周地板：默认 13%，可选覆盖 ----------
if [ -n "${WEEK_FLOOR_PCT:-}" ]; then
  FLOOR="$WEEK_FLOOR_PCT"
elif [ -r "$FLOORF" ]; then
  FLOOR="$(cat "$FLOORF")"
else
  FLOOR=13
  printf '%s\n' "$FLOOR" > "$FLOORF"
fi
case "$FLOOR" in ''|*[!0-9]*) FLOOR=13 ;; esac
[ "$FLOOR" -lt 8 ] && FLOOR=8
[ "$FLOOR" -gt 13 ] && FLOOR=13

rotate_log
log "guard2 rev3 started pid=$$ dry=$DRY dwell=${DWELL}s week_floor=${FLOOR}% h5_max=${H5_MAX}"

while :; do
  ITERS=$(( ITERS + 1 ))
  one_round
  if [ "$MAX_ITERS" -gt 0 ] && [ "$ITERS" -ge "$MAX_ITERS" ]; then
    log "iteration limit reached ($ITERS); exit"
    break
  fi
  sleep "$INTERVAL"
done
