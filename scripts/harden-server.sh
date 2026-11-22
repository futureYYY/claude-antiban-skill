#!/usr/bin/env bash
# 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT
# harden-server.sh <SSH端口> <SS端口> <时区>
# 在服务器上以 root 执行：时区 + swap + ufw + 仅密钥 SSH + 关 IPv6
# 例: bash harden-server.sh 2222 18888 America/Los_Angeles
set -euo pipefail

SSH_PORT="${1:?用法: harden-server.sh <SSH端口> <SS端口> <时区>}"
SS_PORT="${2:?缺少 SS 端口}"
TZ_NAME="${3:-America/Los_Angeles}"

# ---- 前置保护：确认 sshd 真的在这个端口听，否则开 ufw 会把自己锁死 ----
if ! ss -tlnp 2>/dev/null | grep -q ":${SSH_PORT} "; then
  echo "[ABORT] sshd 没有在 ${SSH_PORT} 端口监听。"
  echo "        先改好 sshd 的 Port，确认能连上，再跑这个脚本。"
  exit 1
fi
if ! ss -tlnp 2>/dev/null | grep -q ":${SS_PORT} "; then
  echo "[WARN] ${SS_PORT} 当前没有服务在听（shadowsocks 还没装？）。仍会放行该端口。"
fi
echo "[OK] 前置检查通过"
echo

echo "== 1/5 时区 =="
timedatectl set-timezone "$TZ_NAME"
timedatectl | grep -E 'Time zone|Local time' || true
echo

echo "== 2/5 swap（1G 机器必做）=="
if swapon --show 2>/dev/null | grep -q '/swapfile'; then
  echo "  已存在，跳过"
else
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10 >/dev/null
  grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
  echo "  已加 2G swap，swappiness=10"
fi
echo

echo "== 3/5 ufw（先 allow 再 enable）=="
ufw allow "${SSH_PORT}/tcp"
ufw allow "${SS_PORT}/tcp"
ufw allow "${SS_PORT}/udp"
ufw --force enable
ufw status verbose
echo

echo "== 4/5 SSH 仅密钥 =="
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-pubkey.conf <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sshd -t
systemctl reload ssh 2>/dev/null || systemctl reload sshd
echo "  已改为仅密钥。请立刻另开一个连接验证，不要关掉当前会话。"
echo

echo "== 5/5 关闭 IPv6 =="
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
grep -q 'disable_ipv6=1' /etc/sysctl.conf || printf 'net.ipv6.conf.all.disable_ipv6=1\nnet.ipv6.conf.default.disable_ipv6=1\n' >> /etc/sysctl.conf
echo "  已关闭"
echo

echo "== 完成，复验 =="
echo "  ss -tlnp"
echo "  ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no <alias> echo x"
echo "  期望：Permission denied (publickey) —— 括号里不能再出现 password"
