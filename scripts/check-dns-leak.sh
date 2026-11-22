#!/usr/bin/env bash
# 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT
# check-dns-leak.sh [期望出口IP]
# 检查 DNS / ECS 是否泄露真实位置。
# 退出码: 0=通过  2=确认泄漏  3=无法确认（需要人工看一眼）
set -uo pipefail

EXPECT="${1:-$(curl -s --max-time 15 https://api.ipify.org)}"
[ -n "$EXPECT" ] || { echo "FAIL: 取不到出口 IP"; exit 3; }

SUBNET="$(echo "$EXPECT" | awk -F. '{print $1"."$2"."$3}')"
echo "== 期望出口 IP : ${EXPECT}"
echo "== 期望网段    : ${SUBNET}.0/24"
echo

VERDICT=3

echo "── 1/3 Google ECS 回显（最强信号，但很多环境不返回）"
GTXT="$(nslookup -type=TXT o-o.myaddr.l.google.com 2>/dev/null | tr -d '"')"
if printf '%s' "$GTXT" | grep -q 'edns0-client-subnet'; then
  ECS="$(printf '%s' "$GTXT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+' | head -1)"
  echo "  edns0-client-subnet : ${ECS}"
  case "$ECS" in
    "${SUBNET}.0/24"|"${SUBNET}."*) echo "  → 与出口同网段 ✅"; [ "$VERDICT" -eq 3 ] && VERDICT=0;;
    *) echo "  → 与出口网段不符 ❌"; VERDICT=2;;
  esac
else
  RAW="$(printf '%s' "$GTXT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)"
  echo "  未返回 edns0-client-subnet（常见）。解析器看到的地址: ${RAW:-<空>}"
  echo "  → 这条不足以下结论，继续看第 3 项"
fi
echo

echo "── 2/3 Akamai whoami（辅助）"
nslookup -type=TXT whoami.ds.akahelp.net 2>/dev/null \
  | tr -d '"' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -3 | sed 's/^/  /'
echo

echo "── 3/3 解析器所在国（决定性判据之一）"
GEO_JSON="$(curl -sL --max-time 20 https://edns.ip-api.com/json || true)"
echo "$GEO_JSON" | sed 's/^/  /'
GEO="$(printf '%s' "$GEO_JSON" | tr -d '\n' | grep -oE '"geo"[^,]*' | head -1)"

case "$GEO" in
  *China*|*"CN"*)
      echo "  → ❌ 解析器在中国，DNS 没走代理"
      VERDICT=2
      ;;
  "")
      echo "  → ⚠️ 取不到解析器位置"
      [ "$VERDICT" -ne 2 ] && VERDICT=3
      ;;
  *)
      echo "  → ✅ 解析器不在中国"
      if [ "$VERDICT" -ne 2 ]; then VERDICT=0; fi
      ;;
esac
echo

echo "── 结论 ──"
case "$VERDICT" in
  0) echo "  ✅ 通过（最好再用浏览器开 ipleak.net 复核：DNS 栏应全是出口国解析器）";;
  2) echo "  ❌ 确认泄漏 —— 去改 dns_config.yaml（见 references/02 第五节），改完重启客户端";;
  3) echo "  ⚠️ 无法确认 —— 别当通过。手动开 ipleak.net，看 DNS Addresses 一栏有没有你本地 ISP";;
esac
exit "$VERDICT"
