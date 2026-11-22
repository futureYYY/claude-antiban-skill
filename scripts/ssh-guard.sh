#!/usr/bin/env bash
# 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT
# ssh-guard.sh —— 连服务器前的硬闸门。**每次 ssh 之前都要先跑它**，不通过就不要连。
#
# 它做三件事：
#   1. 静态：~/.ssh/config 里这个别名的 ProxyCommand 必须存在且指向本地代理；缺了就自动补，补不上直接失败
#   2. 端口：本地代理端口必须在监听（Windows: netstat / macOS·Linux: nc）
#   3. 实时（--live）：真连一次，服务器看到的来源必须是中间节点，不能是用户家宽 IP
#
# 用法：
#   bash ssh-guard.sh                 # 默认别名 us-vps
#   bash ssh-guard.sh <别名>
#   bash ssh-guard.sh <别名> --live   # 额外做一次真实连接检查（会多花几秒）
#
# 退出码：0 通过；1 检查不通过（禁止继续）；2 缺 connect 工具
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

ALIAS="us-vps"
LIVE=0
for a in "$@"; do
  case "$a" in
    --live) LIVE=1 ;;
    *) ALIAS="$a" ;;
  esac
done

PROXY_HOST="127.0.0.1"
PROXY_PORT="7897"

fail() { echo "✗ $*" >&2; echo "  → 停止操作，先把这一条修好再连服务器。" >&2; exit 1; }

# ---------- 1. 静态检查 ----------
PC="$(ssh -G "$ALIAS" 2>/dev/null | awk 'tolower($1)=="proxycommand"{$1=""; sub(/^ /,""); print; exit}')"
if [ -z "$PC" ] || [ "$PC" = "none" ]; then
  echo "· $ALIAS 没有 ProxyCommand，正在自动补…"
  bash "$DIR/ensure-ssh-proxy.sh" "$ALIAS" "${PROXY_HOST}:${PROXY_PORT}" || fail "ProxyCommand 补不上"
  PC="$(ssh -G "$ALIAS" 2>/dev/null | awk 'tolower($1)=="proxycommand"{$1=""; sub(/^ /,""); print; exit}')"
fi
case "$PC" in
  none|"") fail "$ALIAS 的 ProxyCommand 是空或 none —— 这样会从真实 IP 直连" ;;
esac
echo "✓ ProxyCommand：$PC"

# ---------- 2. 代理端口 ----------
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    if ! netstat -ano 2>/dev/null | grep -qE "[:.]${PROXY_PORT}[[:space:]].*LISTENING"; then
      fail "本地 ${PROXY_HOST}:${PROXY_PORT} 没在监听 —— 梯子没开（或没开系统代理/混合端口）。开了再来。"
    fi ;;
  *)
    if command -v nc >/dev/null 2>&1; then
      nc -z "$PROXY_HOST" "$PROXY_PORT" 2>/dev/null || fail "连不上 ${PROXY_HOST}:${PROXY_PORT} —— 梯子没开"
    elif command -v /dev/tcp >/dev/null 2>&1 || true; then
      (exec 3<>"/dev/tcp/${PROXY_HOST}/${PROXY_PORT}") 2>/dev/null || fail "连不上 ${PROXY_HOST}:${PROXY_PORT} —— 梯子没开"
    fi ;;
esac
echo "✓ 本地代理端口 ${PROXY_HOST}:${PROXY_PORT} 在监听"

# ---------- 3. 实时检查 ----------
if [ "$LIVE" = "1" ]; then
  SRC="$(ssh -o ConnectTimeout=12 -o BatchMode=yes "$ALIAS" 'echo $SSH_CONNECTION' 2>/dev/null | awk '{print $1}')"
  [ -n "$SRC" ] || fail "ssh 连不上（代理在，但链路或服务器有问题）"
  SRV_IP="$(ssh -G "$ALIAS" 2>/dev/null | awk 'tolower($1)=="hostname"{print $2; exit}')"
  if [ "$SRC" = "$SRV_IP" ]; then
    echo "✓ 服务器看到的来源是中间节点（$SRC），没有暴露家宽 IP"
  else
    echo "⚠ 服务器看到的来源是 $SRC（服务器自己的 IP 是 $SRV_IP）" >&2
    echo "  可能是链式只走了一级；如果这是你家宽的公网 IP，立刻停下修代理。" >&2
  fi
fi

echo "✓ 闸门通过，可以连 $ALIAS"
