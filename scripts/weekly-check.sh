#!/usr/bin/env bash
# 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT
# weekly-check.sh [ssh别名] [SS端口]
# 每周体检：出口国 / DNS 泄漏 / IPv6 / 服务器侧链式 / Claude Code 连通
# 例: bash weekly-check.sh us-vps 18888
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$0"
ALIAS="${1:-}"
PORT="${2:-18888}"

echo "=============================================="
echo " 每周体检  $(date '+%Y-%m-%d %H:%M')"
echo "=============================================="

IP="$(curl -s --max-time 15 https://api.ipify.org)"
[ -n "$IP" ] || { echo "FAIL: 取不到出口 IP —— 梯子关了？"; exit 1; }
echo "出口 IP: ${IP}"
echo

FAILED=0

echo "── 1/5 出口国 ──"
TRACE="$(curl -s -m 20 https://www.cloudflare.com/cdn-cgi/trace)"
printf '%s\n' "$TRACE" | grep -E '^(ip|loc|colo)=' | sed 's/^/  /'
LOC="$(printf '%s\n' "$TRACE" | grep '^loc=' | cut -d= -f2)"
if [ "$LOC" = "US" ]; then echo "  ✅ 出口在美国"; else echo "  ❌ 出口不是 US（现在是 ${LOC:-未知}）"; FAILED=1; fi
echo

echo "── 2/5 DNS 泄漏 ──"
if bash "$DIR/check-dns-leak.sh" "$IP"; then
  :
else
  RC=$?
  if [ "$RC" -eq 3 ]; then
    echo "  ⚠️ DNS 状态无法确认 —— 不计为通过，手动开 ipleak.net 看一眼"
  else
    echo "  ❌ DNS 确认泄漏"
  fi
  FAILED=1
fi
echo

echo "── 3/5 IPv6 默认路由 ──"
if command -v ip >/dev/null 2>&1; then
  V6="$(ip -6 route show default 2>/dev/null || true)"
  if [ -z "$V6" ]; then echo "  ✅ 无 IPv6 默认路由"; else echo "  ⚠️ 存在 IPv6 默认路由："; echo "$V6" | sed 's/^/    /'; FAILED=1; fi
else
  echo "  （Windows：在 PowerShell 跑 Get-NetRoute -AddressFamily IPv6 | ? {\$_.DestinationPrefix -eq '::/0'}）"
  echo "  应只指向 TUN，不能指向物理网卡"
fi
echo

if [ -z "$ALIAS" ]; then
  echo "── 4-5/5 服务器侧 ──"
  echo "  跳过（没给 SSH 别名）。补跑："
  echo "    bash \"$SELF\" <别名> <SS端口>"
  echo "  或手动："
  echo "    ssh <别名> \"bash -s -- ${PORT}\" < \"$DIR/check-chain.sh\""
  echo "    ssh <别名> \"claude-safe -p 'Reply with exactly: OK'\""
else
  echo "── 4/5 服务器侧链式来源 ──"
  if ssh -o ConnectTimeout=15 -o BatchMode=yes "$ALIAS" "bash -s -- ${PORT}" < "$DIR/check-chain.sh"; then
    echo "  （若上面出现你的家宽 IP → ❌ 退化成直连）"
  else
    echo "  ❌ SSH 失败 —— 链路抖动或别名不对，重试一次"; FAILED=1
  fi
  echo

  echo "── 5/5 Claude Code 连通 ──"
  OUT="$(ssh -o ConnectTimeout=20 -o BatchMode=yes "$ALIAS" "claude-safe -p 'Reply with exactly: OK'" 2>&1 || true)"
  if printf '%s' "$OUT" | grep -q "OK"; then
    echo "  ✅ 返回 OK"
  else
    echo "  ❌ 没返回 OK："; printf '%s\n' "$OUT" | head -5 | sed 's/^/    /'; FAILED=1
  fi
fi

echo
echo "=============================================="
if [ "$FAILED" -eq 0 ]; then
  echo " ✅ 本周通过"
else
  echo " ❌ 有项目未通过 —— 对照 references/06 的坑表处理"
fi
echo "=============================================="
