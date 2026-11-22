#!/usr/bin/env bash
# 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT
# check-chain.sh [SS端口]
# 在【服务器】上执行：证明链式代理真的生效。
# 判据：来源应该是中间节点（如日本），不应出现你自己的家宽 IP。
set -uo pipefail

PORT="${1:-18888}"   # 改成自己的 SS 端口

echo "== 检查 :${PORT} 的来源地址 =="
OUT="$(ss -tn "sport = :${PORT}" 2>/dev/null | tail -n +2 || true)"

if [ -z "$OUT" ]; then
  echo "  没有活动连接。先在客户端访问一下网页，再回来跑这个。"
  exit 1
fi

printf '%s\n' "$OUT" \
  | awk '{print $5}' \
  | sed 's/:[0-9]*$//' \
  | sort | uniq -c | sort -rn \
  | sed 's/^/  /'

echo
echo "判据："
echo "  ✅ 来源全是中间节点（如日本）= 链式生效"
echo "  ❌ 出现你的家宽 IP        = 退化成直连，或 Clash 没开"
echo
echo "注意：出口 IP 等于本机 IP 只说明「流量到了这台服务器」，"
echo "      不说明经过了中间节点。唯一硬判据是上面这张来源表。"
