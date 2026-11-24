#!/bin/bash
# claude-quota-guard2 — 多账号 / 多会话额度守护 (2026-11-24)
# 规则：
#   - 检测间隔 720-1200 秒随机
#   - 剩余 20%-30% 触发（利用率阈值 0.70-0.80，每次重抽）
#   - 切换后最小驻留 30 分钟
#   - 双号都满：等最近重置 + 30-60 分钟随机，再切
#   - 续跑：只给未完成会话发「继续」，串行，间隔 5-10 秒随机
#   - 重启会话保留原 --model / --effort / --permission-mode
set -uo pipefail

TOK=/root/.claude/tokens
DIR=/root/.claude/failover
ACTIVE="$TOK/active"
LOG="$DIR/guard2.log"
STATE="$DIR/guard2.state"
DWELL=1800              # 最小驻留 30 分钟
WAIT_MIN=1800           # 重置后再等 30 分钟
WAIT_MAX=3600           # 上限 60 分钟
DRY="${DRY_RUN:-0}"

mkdir -p "$DIR"
log(){ echo "$(TZ=Asia/Shanghai date '+%F %T') $*" >> "$LOG"; [ "$DRY" = "1" ] && echo "$(TZ=Asia/Shanghai date '+%H:%M:%S') $*"; }

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

# 取会话当前 claude 进程参数
pane_args(){
  local s="$1" pid cwd p
  pid="$(tmux list-panes -t "$s" -F '#{pane_pid}' 2>/dev/null | head -1)"
  [ -z "$pid" ] && { echo ""; return; }
  for p in $(pgrep -P "$pid" 2>/dev/null) $(pgrep -f 'bin/claude' 2>/dev/null); do
    [ -r "/proc/$p/cwd" ] || continue
    cwd="$(readlink -f "/proc/$p/cmdline" )"
    if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'claude'; then
      tr '\0' ' ' < "/proc/$p/cmdline" | sed -e 's/^[^ ]* //' -e 's/[[:space:]]*$//'
      return
    fi
  done
  echo ""
}

norm_args(){
  local raw="$1" out="-c"
  echo "$raw" | grep -q -- '--model' && out="$out $(echo "$raw" | grep -oE -- '--model[= ][^ ]+' | head -1 | sed 's/--model[= ]/--model /')" || out="$out --model opus"
  echo "$raw" | grep -q -- '--effort' && out="$out $(echo "$raw" | grep -oE -- '--effort[= ][^ ]+' | head -1 | sed 's/--effort[= ]/--effort /')" || out="$out --effort max"
  echo "$raw" | grep -q -- '--permission-mode' && out="$out $(echo "$raw" | grep -oE -- '--permission-mode[= ][^ ]+' | head -1 | sed 's/--permission-mode[= ]/--permission-mode /')"
  echo "$out"
}

switch_to(){
  local target="$1" reason="$2"
  local cur; cur="$(cur_acct)"
  log "SWITCH $cur -> $target ($reason)"
  [ "$DRY" = "1" ] && { log "[dry] would link active -> $target"; return 0; }

  ln -sfn "$TOK/$target.env" "$ACTIVE"
  local s cwd raw args busy
  for s in $(sessions); do
    busy=0; pane_busy "$s" && busy=1
    cwd="$(tmux display-message -p -t "$s" '#{pane_current_path}' 2>/dev/null)"
    raw="$(pane_args "$s")"
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
    sleep $(( RANDOM % 6 + 5 ))   # 5-10 秒随机
  done
  echo "$(date +%s)" > "$STATE"
  log "switch done"
}

if [ "${1:-}" = "--status" ]; then
  printf '%-18s %-6s %-8s %-8s %s\n' ACCOUNT HTTP 5H 7D RESET_5H
  for a in $(accounts); do
    read -r c u5 u7 r5 r7 <<< "$(probe "$a")"
    printf '%-18s %-6s %-8s %-8s %s\n' "$a" "$c" "$u5" "$u7" "$(TZ=Asia/Shanghai date -d "@$r5" '+%m-%d %H:%M' 2>/dev/null)"
  done
  echo "active: $(cur_acct)"
  exit 0
fi

log "guard2 started dry=$DRY dwell=${DWELL}s"
while :; do
  interval=$(( RANDOM % 481 + 720 ))          # 720-1200 秒
  cur="$(cur_acct)"
  read -r code u5 u7 r5 r7 <<< "$(probe "$cur")"
  util="$(mx "$u5" "$u7")"
  th="$(awk -v r=$(( RANDOM % 11 )) 'BEGIN{printf "%.3f", 0.70 + r/100}')"   # 剩余 20-30%
  last="$(cat "$STATE" 2>/dev/null || echo 0)"
  age=$(( $(date +%s) - last ))

  log "check cur=$cur http=$code 5h=$u5 7d=$u7 util=$util th=$th dwell_left=$(( DWELL - age > 0 ? DWELL - age : 0 ))s next=${interval}s"

  if [ "$code" = "200" ] && ge "$util" "$th" && [ "$age" -ge "$DWELL" ]; then
    best=""; bestu=9
    for a in $(accounts); do
      [ "$a" = "$cur" ] && continue
      read -r cc c5 c7 cr5 cr7 <<< "$(probe "$a")"
      cu="$(mx "$c5" "$c7")"
      [ "$cc" = "200" ] && lt "$cu" 0.5 && lt "$cu" "$bestu" && { bestu="$cu"; best="$a"; }
    done
    if [ -n "$best" ]; then
      switch_to "$best" "util=$util>=th=$th"
    else
      # 双号都紧张：找最近重置
      next=0
      for a in $(accounts); do
        read -r cc c5 c7 cr5 cr7 <<< "$(probe "$a")"
        cu="$(mx "$c5" "$c7")"
        ge "$cu" "$th" || continue
        for t in "$cr5" "$cr7"; do
          [ "$t" -gt "$(date +%s)" ] 2>/dev/null || continue
          if [ "$next" = "0" ] || [ "$t" -lt "$next" ]; then next="$t"; fi
        done
      done
      if [ "$next" != "0" ]; then
        wait_until=$(( next + RANDOM % (WAIT_MAX - WAIT_MIN + 1) + WAIT_MIN ))
        log "both tight; next reset=$(TZ=Asia/Shanghai date -d @$next '+%F %T') wait_until=$(TZ=Asia/Shanghai date -d @$wait_until '+%F %T')"
        if [ "$(date +%s)" -ge "$wait_until" ]; then
          switch_to "$cur" "post-reset-wait"   # 目标即当前号（已刷新）
        fi
      else
        log "no reset info yet; skip"
      fi
    fi
  fi
  sleep "$interval"
done
