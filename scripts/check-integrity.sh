#!/usr/bin/env bash
# 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT
# check-integrity.sh —— 校验 skill 文件是否被修改过（在 skill 根目录或 scripts/ 下都能跑）
set -u

cd "$(dirname "$0")/.." || exit 1

if [ ! -f MANIFEST.sha256 ]; then
  echo "找不到 MANIFEST.sha256，可能不是完整包"; exit 2
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "缺少 sha256sum：请用 Git Bash / WSL / Linux 运行"; exit 2
fi

tmp=$(mktemp)
if sha256sum -c MANIFEST.sha256 >"$tmp" 2>&1; then
  n=$(wc -l < MANIFEST.sha256 | tr -d ' ')
  echo "OK：$n 个文件与作者发布版一致"
  rm -f "$tmp"; exit 0
else
  echo "FAILED：以下文件与原版不一致 ——"
  grep -v ': OK$' "$tmp" || true
  rm -f "$tmp"; exit 1
fi
