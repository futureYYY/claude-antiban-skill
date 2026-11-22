#!/usr/bin/env bash
# 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT
# ensure-ssh-proxy.sh —— 把 ProxyCommand 钉进 ~/.ssh/config 的指定 Host 块（幂等，可反复跑）
#
# 为什么必须做：Windows 的 OpenSSH / 系统代理互不相干，只开「系统代理」时 ssh 照样从真实 IP 直连；
# 只靠 TUN 也不保险（TUN 关了、或 Clash 被切到直连，ssh 会静默走真实 IP）。
# 钉进 ProxyCommand 之后是 fail-closed：本地代理端口不在 → 直接连不上，而不是悄悄退回直连。
#
# 用法：
#   bash ensure-ssh-proxy.sh [别名] [代理地址]
#   bash ensure-ssh-proxy.sh us-vps 127.0.0.1:7897
#
# 退出码：0 成功（已存在或新写入）；2 缺少 connect 工具；3 写入后校验失败
set -uo pipefail

ALIAS="${1:-us-vps}"
PROXY="${2:-127.0.0.1:7897}"
PROXY_HOST="${PROXY%%:*}"
PROXY_PORT="${PROXY##*:}"
SSH_DIR="$HOME/.ssh"
CONFIG="$SSH_DIR/config"
LINE="ProxyCommand connect -H ${PROXY_HOST}:${PROXY_PORT} %h %p"

mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR" 2>/dev/null || true
[ -f "$CONFIG" ] || { : > "$CONFIG"; chmod 600 "$CONFIG"; }

# 依赖：connect（connect-proxy）。没有它就别写配置，否则 ssh 直接报错连不上
if ! command -v connect >/dev/null 2>&1; then
  cat >&2 <<'EOF'
✗ 本机没有 connect（HTTP 代理用的那个小工具），先装上再跑本脚本：
    macOS        brew install connect
    Debian/Ubuntu sudo apt install connect-proxy
    Windows      Git Bash 通常自带（/mingw64/bin/connect）；没有就装 Git for Windows 最新版
  装完 `command -v connect` 有输出再来。
EOF
  exit 2
fi

# 1) 找到 Host 块的起止行；换行符统一先归一化（Windows 编辑器可能存成 CRLF）
TMP="$(mktemp)"
tr -d '\r' < "$CONFIG" > "$TMP"
START="$(awk -v a="$ALIAS" 'tolower($1)=="host"{for(i=2;i<=NF;i++) if(tolower($i)==tolower(a)) {print NR; exit}}' "$TMP")"

if [ -n "${START:-}" ]; then
  END="$(awk -v s="$START" 'NR>s && tolower($1)=="host"{print NR-1; exit} END{if(!found) print NR}' "$TMP")"
  PC="$(awk -v s="$START" -v e="$END" 'NR>s && NR<=e && tolower($1)=="proxycommand"{print NR; exit}' "$TMP")"
  if [ -n "${PC:-}" ]; then
    if sed -n "${PC}p" "$TMP" | grep -qF -- "$LINE"; then
      echo "· $ALIAS 已有正确的 ProxyCommand，跳过写入"
      rm -f "$TMP"
    else
      cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
      sed -i "${PC}s|.*|    $LINE|" "$TMP"
      mv "$TMP" "$CONFIG"; chmod 600 "$CONFIG"
      echo "· $ALIAS 原来的 ProxyCommand 已替换"
    fi
  else
    cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
    awk -v s="$START" -v line="    $LINE" 'NR==s{print; print line; next}{print}' "$TMP" > "$TMP.new"
    mv "$TMP.new" "$CONFIG"; chmod 600 "$CONFIG"; rm -f "$TMP"
    echo "· $ALIAS 块内新增 ProxyCommand"
  fi
else
  cp "$CONFIG" "$CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
  cat >> "$CONFIG" <<EOF

Host $ALIAS
    $LINE
EOF
  chmod 600 "$CONFIG"; rm -f "$TMP"
  echo "· 新增 Host $ALIAS 块（只含 ProxyCommand，其余字段沿用原来的或另行补）"
fi

# 2) 校验：ssh 解析出来必须真的是这一条
GOT="$(ssh -G "$ALIAS" 2>/dev/null | awk 'tolower($1)=="proxycommand"{$1=""; sub(/^ /,""); print; exit}')"
if [ "$GOT" != "connect -H ${PROXY_HOST}:${PROXY_PORT} %h %p" ]; then
  echo "✗ 校验失败：ssh -G $ALIAS 解析出的 ProxyCommand 是「${GOT:-空}」" >&2
  exit 3
fi

echo "✓ $ALIAS 的 ProxyCommand 已生效：$GOT"
echo "  再验一次 fail-closed：把代理关掉后 ssh 应当直接连不上（不是退回直连）。"
