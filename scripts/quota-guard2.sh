#!/bin/bash
# claude-quota-guard2 — 多账号 / 多会话额度守护 (2026-11-24, rev2)
# 规则：
#   - 每轮抽 X = 10-20：剩 X% 触发，间隔 X 分钟（同源）
#   - 切换后最小驻留 30 分钟
#   - 双号都满：等最近重置 + 30-60 分钟随机，再切（等待状态持久化）
#   - 续跑：只给未完成会话发「继续」，串行，间隔 5-10 秒随机
#   - 重启会话保留原 --model / --effort / --permission-mode
#   - 只重启正在跑 claude 的会话，纯 shell 会话跳过
set -uo pipefail

TOK=/root/.claude/tokens
DIR=/root/.claude/failover
ACTIVE="$TOK/active"
LOG="$DIR/guard2.log"
STATE="$DIR/guard2.state"
WAITF="$DIR/guard2.wait"
DWELL=1800
WAIT_MIN=1800
WAIT_MAX=3600
DRY="${DRY_RUN:-0}"

mkdir -p "$DIR"
log(){ echo "$(TZ=America/Los_Angeles date '+%F %T') $*" >> "$LOG"; [ "$DRY" = "1" ] && echo "$(TZ=America/Los_Angeles date '+%H:%M:%S') $*"; }

probe(){
  local f="$TOK/$1.env" hdr code u5 u7 r5 r7
  [ -r "$f" ] || { echo "000 0 0 0 0"; return; }
  hdr="$(curl -s -D - -o /dev/null --max-time 40 https://api.anthropic.com/v1/messages \
    -H "Authorization: Bearer $(cat "$f")" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "content-type: application/json" \
    -d '{"model":"claude-haiku-4-5","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' 2>/dev/null)"
  code="$(printf '%s\n' "$hdr" | head -1 | awk '{print $2}')"
  u5="$(printf '%s\n' "$hdr" | grep -i '^anthropic-ratelimit-unified-5h-utilization:' | tr -d '\r' | awk '{print $2}')"
  u7="$(printf '%s\n' "$hdr" | grep -i '^anthropic-ratelimit-unified-7d-utilization:' | tr -d '\r' | awk '{print $2}')"
  r5="$(printf '%s\n' "$hdr" | grep -i '^anthropic-ratelimit-unified-5h-reset:' | tr -d '\r' | awk '{print $2}')"
  r7="$(printf '%s\n' "$hdr" | grep -i '^anthropic-ratelimit-unified-7d-reset:' | tr -d '\r' | awk '{print $2}')"
  echo "${code:-000} ${u5:-0} ${u7:-0} ${r5:-0} ${r7:-0}"
}

mx(){ awk -v a="$1" -v b="$2" 'BEGIN{printf "%.4f", (a>b?a:b)}'; }
ge(){ awk -v u="$1" -v t="$2" 'BEGIN{exit !(u>=t)}'; }
lt(){ awk -v u="$1" -v t="$2" 'BEGIN{exit !(u<t)}'; }
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

if [ "${1:-}" = "--status" ]; then
  printf '%-18s %-6s %-8s %-8s %s\n' ACCOUNT HTTP 5H 7D RESET_5H
  for a in $(accounts); do
    read -r c u5 u7 r5 r7 <<< "$(probe "$a")"
    printf '%-18s %-6s %-8s %-8s %s\n' "$a" "$c" "$u5" "$u7" "$(TZ=America/Los_Angeles date -d "@$r5" '+%m-%d %H:%M' 2>/dev/null)"
  done
  echo "active: $(cur_acct)"
  exit 0
fi

log "guard2 rev2 started dry=$DRY dwell=${DWELL}s"
while :; do
  X=$(( RANDOM % 11 + 10 ))
  interval=$(( X * 60 ))
  cur="$(cur_acct)"
  read -r code u5 u7 r5 r7 <<< "$(probe "$cur")"
  util="$(mx "$u5" "$u7")"
  th="$(awk -v x="$X" 'BEGIN{printf "%.3f", 1 - x/100}')"
  last="$(cat "$STATE" 2>/dev/null || echo 0)"
  age=$(( $(date +%s) - last ))

  log "check cur=$cur http=$code 5h=$u5 7d=$u7 util=$util th=$th dwell_left=$(( DWELL - age > 0 ? DWELL - age : 0 ))s next=${interval}s"

  # 等待重置阶段：优先处理
  if [ -f "$WAITF" ]; then
    read -r w_target w_until <<< "$(cat "$WAITF")"
    now=$(date +%s)
    if [ "$now" -ge "${w_until:-0}" ]; then
      log "wait elapsed -> switch to $w_target"
      switch_to "$w_target" "post-reset-wait"
    else
      log "waiting for reset: target=$w_target until=$(TZ=America/Los_Angeles date -d @$w_until '+%F %T')"
    fi
    sleep "$interval"; continue
  fi

  if [ "$code" = "200" ] && ge "$util" "$th" && [ "$age" -ge "$DWELL" ]; then
    best=""; bestu=9
    for a in $(accounts); do
      [ "$a" = "$cur" ] && continue
      read -r cc c5 c7 cr5 cr7 <<< "$(probe "$a")"
      cu="$(mx "$c5" "$c7")"
      if [ "$cc" = "200" ] && lt "$cu" 0.5 && lt "$cu" "$bestu"; then bestu="$cu"; best="$a"; fi
    done
    if [ -n "$best" ]; then
      switch_to "$best" "util=$util>=th=$th"
    else
      next=0; ntarget=""
      for a in $(accounts); do
        read -r cc c5 c7 cr5 cr7 <<< "$(probe "$a")"
        cu="$(mx "$c5" "$c7")"
        ge "$cu" "$th" || continue
        for t in "$cr5" "$cr7"; do
          [ "${t:-0}" -gt "$(date +%s)" ] 2>/dev/null || continue
          if [ "$next" = "0" ] || [ "$t" -lt "$next" ]; then next="$t"; ntarget="$a"; fi
        done
      done
      if [ "$next" != "0" ] && [ -n "$ntarget" ]; then
        wait_until=$(( next + RANDOM % (WAIT_MAX - WAIT_MIN + 1) + WAIT_MIN ))
        printf '%s %s\n' "$ntarget" "$wait_until" > "$WAITF"
        log "both tight; target=$ntarget reset=$(TZ=America/Los_Angeles date -d @$next '+%F %T') wait_until=$(TZ=America/Los_Angeles date -d @$wait_until '+%F %T')"
      else
        log "both tight but no future reset found; retry next round"
      fi
    fi
  fi
  sleep "$interval"
done
