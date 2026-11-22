#!/usr/bin/env bash
# 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT
# install-ss.sh [端口] [密码]
# 在服务器上执行：安装 shadowsocks 出口并做一次回环自测。
# 不传密码则随机生成。
set -euo pipefail

PORT_ARG="${1:-}"
PASS_ARG="${2:-}"

# 幂等：已装过就复用现有端口和密码，避免重跑把客户端配置打废
CFG=/etc/shadowsocks-libev/config.json
EXIST_PASS=""; EXIST_PORT=""
if [ -f "$CFG" ]; then
  EXIST_PASS="$(sed -n 's/.*"password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)"
  EXIST_PORT="$(sed -n 's/.*"server_port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$CFG" | head -1)"
fi

PORT="${PORT_ARG:-${EXIST_PORT:-18888}}"
if [ -n "$PASS_ARG" ]; then
  PASS="$PASS_ARG"
elif [ -n "$EXIST_PASS" ]; then
  PASS="$EXIST_PASS"
  echo "[i] 检测到已安装，复用现有密码（如需更换，显式传第二个参数）"
else
  PASS="$(openssl rand -hex 16)"
fi
METHOD="chacha20-ietf-poly1305"

echo "== 1/4 安装 shadowsocks-libev =="
apt-get update -y
apt-get install -y shadowsocks-libev

echo "== 2/4 写配置（覆盖 apt 自带的 127.0.0.1:8388 默认实例）=="
mkdir -p /etc/shadowsocks-libev
cat > /etc/shadowsocks-libev/config.json <<EOF
{
    "server": ["0.0.0.0"],
    "server_port": ${PORT},
    "password": "${PASS}",
    "method": "${METHOD}",
    "mode": "tcp_and_udp"
}
EOF
chmod 600 /etc/shadowsocks-libev/config.json

systemctl enable shadowsocks-libev >/dev/null 2>&1 || true
systemctl restart shadowsocks-libev
sleep 2

echo "== 3/4 状态 =="
systemctl is-active shadowsocks-libev || true
ss -tulnp | grep ":${PORT}" || echo "  [!] 端口没在监听，检查 systemctl status"

echo "== 4/4 回环自测 =="
ss-local -s 127.0.0.1 -p "${PORT}" -k "${PASS}" -m "${METHOD}" -l 1080 >/dev/null 2>&1 &
SSPID=$!
sleep 3
OUT="$(curl -s --max-time 20 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org || true)"
kill "$SSPID" 2>/dev/null || true
echo "  经本地 socks 的出口 IP: ${OUT:-<失败>}"
[ -n "$OUT" ] || echo "  [!] 自测失败：服务端没起来，先别去调客户端"

B64="$(printf '%s:%s' "${METHOD}" "${PASS}" | base64 -w0)"
echo
echo "── Clash 节点 URI（把 <VPS_IP> 换成服务器 IP）──"
echo "ss://${B64}@<VPS_IP>:${PORT}#us-residential"
echo
echo "── 端口记得放行 ──"
echo "ufw allow ${PORT}/tcp && ufw allow ${PORT}/udp"
echo
echo "提示：密码只存在这台机器和自己的密码管理器里，不要贴进任何文档或聊天。"
