#!/usr/bin/env bash
# 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT
# check-ip-quality.sh [IP]
# 验收一台「住宅 IP」是否达标。不传参数则检查本机当前出口 IP。
# 依赖: curl + (python3 或 python)。Windows 上 python3 可能是商店占位程序，
#       脚本会自动探测可用的解释器，也可用 CLAUDE_PY 指定。
#
# 交叉验证结构：
#   1. ipinfo          → asn.type / company.type（唯一提供"类型"字段的源）
#   2. ipapi.is        → 第二家独立库，核对 ASN 编号 / 运营商名 / 地理位置是否一致
#   3. Scamalytics     → 独立判定：是否机房、是否代理、连接类型是否 dsl
#   4. PTR             → 弱信号：住宅通常有运营商格式反解
#   5. Cloudflare      → 出口国/机房城市
# 达标 = 类型字段是 isp/isp + 第二源不打架 + Scamalytics 非机房且 Connection=dsl
set -uo pipefail

# ---- 找一个真能用的 python ----
PYBIN=""
for c in "${CLAUDE_PY:-}" python3 python py; do
  [ -n "$c" ] || continue
  if [ "$("$c" -c 'print(1)' 2>/dev/null)" = "1" ]; then PYBIN="$c"; break; fi
done
if [ -z "$PYBIN" ]; then
  for c in "$HOME/miniconda3/python.exe" "$HOME/anaconda3/python.exe" \
           "/c/ProgramData/miniconda3/python.exe" "/d/migration/software/Miniconda/python.exe"; do
    [ -x "$c" ] || continue
    if [ "$("$c" -c 'print(1)' 2>/dev/null)" = "1" ]; then PYBIN="$c"; break; fi
  done
fi
[ -n "$PYBIN" ] || echo "[WARN] 没找到可用的 python，ASN 等字段解析会降级"

IP="${1:-}"
if [ -z "$IP" ]; then
  IP="$(curl -s --max-time 15 https://api.ipify.org)"
  [ -n "$IP" ] || { echo "FAIL: 取不到本机出口 IP"; exit 1; }
fi
echo "== 检查 IP: ${IP} =="
[ -n "$PYBIN" ] && echo "== python : ${PYBIN}"
echo

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------- 1. ipinfo ----------
echo "── 1/5 ipinfo（类型字段的唯一来源）"
curl -s --max-time 25 -A "$UA" "https://ipinfo.io/widget/demo/${IP}" -o "$TMP/ipinfo.json"
if [ -n "$PYBIN" ]; then
  "$PYBIN" - "$TMP/ipinfo.json" <<'PY'
import json, sys
try:
    raw = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception:
    print("  [FAIL] 解析失败（可能被限流），重跑一次"); raise SystemExit
d = raw.get('data', raw)
asn = d.get('asn') or {}; comp = d.get('company') or {}; priv = d.get('privacy') or {}
print(f"  ASN          : {asn.get('asn','?')} {asn.get('name','?')}")
print(f"  asn.type     : {asn.get('type','?')}")
print(f"  company      : {comp.get('name','?')}")
print(f"  company.type : {comp.get('type','?')}")
print(f"  地理位置     : {d.get('city','?')}, {d.get('region','?')}, {d.get('country','?')}")
flags = [k for k, v in priv.items() if v is True]
print(f"  privacy      : {', '.join(flags) if flags else 'none'}")
t, ct = asn.get('type'), comp.get('type')
if t == 'isp' and ct == 'isp':
    print("  → 双ISP ✅")
elif t == 'hosting':
    print("  → 机房 IP ❌")
else:
    print(f"  → 未达严格双ISP（asn={t}, company={ct}）⚠️")
PY
else
  grep -oE '"(type|name|asn)":"[^"]*"' "$TMP/ipinfo.json" | head -12 | sed 's/^/  /'
fi
echo

# ---------- 2. 第二数据源交叉验证 ----------
echo "── 2/5 ipapi.is（第二家独立库，核对是否打架）"
curl -s --max-time 20 -A "$UA" "https://api.ipapi.is/?q=${IP}" -o "$TMP/ipapi.json"
if [ -n "$PYBIN" ]; then
  "$PYBIN" - "$TMP/ipinfo.json" "$TMP/ipapi.json" <<'PY'
import json, re, sys
def load(p):
    try: return json.load(open(p, encoding='utf-8'))
    except Exception: return {}
a = load(sys.argv[1]); a = a.get('data', a)
b = load(sys.argv[2])
if not b:
    print("  [WARN] 第二源不可达，这一项无法交叉（不算通过）"); raise SystemExit
a_asn = ((a.get('asn') or {}).get('asn') or '')
a_name = ((a.get('asn') or {}).get('name') or '')
b_asn_full = b.get('asn') or ''
b_asn = (re.match(r'(AS\d+)', b_asn_full) or [None, ''])[1] if b_asn_full else ''
b_org = b.get('company') or ''
print(f"  ipinfo : {a_asn} {a_name}")
print(f"  ipapi  : {b_asn} {b_org}")
print(f"  国家   : {a.get('country','?')} vs {b.get('country_code') or b.get('country','?')}")
ok = True
if a_asn and b_asn:
    if a_asn.upper() == b_asn.upper():
        print("  ASN 编号一致 ✅")
    else:
        print(f"  ASN 编号不一致 ❌（{a_asn} vs {b_asn}）—— 有一家库过时或 IP 刚变更"); ok = False
else:
    print("  取不到两家 ASN，跳过编号比对 ⚠️"); ok = False
CODES = {'united states': 'US', 'usa': 'US', 'japan': 'JP', 'hong kong': 'HK',
         'singapore': 'SG', 'germany': 'DE', 'united kingdom': 'GB', 'canada': 'CA',
         'netherlands': 'NL', 'france': 'FR', 'south korea': 'KR', 'korea': 'KR',
         'taiwan': 'TW', 'australia': 'AU', 'india': 'IN', 'brazil': 'BR'}

def to_code(s):
    s = (s or '').strip().lower()
    if len(s) == 2:
        return s.upper()
    return CODES.get(s)

ca = to_code(a.get('country'))
cb = to_code(b.get('country') or b.get('country_code'))
if ca and cb:
    if ca == cb:
        print(f"  国家一致 ✅（{ca}）")
    else:
        print(f"  国家不一致 ⚠️（{ca} vs {cb}）")
else:
    print(f"  国家无法比对（ipinfo={a.get('country')}, ipapi={b.get('country')}）")
if a_name and b_org:
    na = re.sub(r'[^a-z]', '', a_name.lower()); nb = re.sub(r'[^a-z]', '', b_org.lower())
    if na and nb and (na[:6] == nb[:6] or na in nb or nb in na):
        print("  运营商名一致 ✅")
    else:
        print(f"  运营商名有出入（{a_name} vs {b_org}）—— 常见，仅供参考")
PY
else
  echo "  (无 python，跳过)"
fi
echo

# ---------- 3. Scamalytics ----------
echo "── 3/5 Scamalytics（独立判定：机房 / 代理 / 连接类型）"
curl -s --max-time 25 -A "$UA" "https://scamalytics.com/ip/${IP}" -o "$TMP/scam.html"
if [ -n "$PYBIN" ]; then
  "$PYBIN" - "$TMP/scam.html" <<'PY'
import re, sys
html = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
m = re.search(r'Fraud Score:\s*(?:<[^>]*>\s*)?(\d+)', html)
print(f"  Fraud Score   : {m.group(1) if m else '?'} / 100   （越低越好）")
want = ['Server', 'Public Proxy', 'Web Proxy', 'Residential Proxy',
        'Anonymizing VPN', 'Tor Exit Node', 'Connection type', 'Datacenter']
rows = re.findall(
    r'<th[^>]*>\s*([A-Za-z][A-Za-z ]{1,24}?)\s*</th>\s*'
    r'<td[^>]*>\s*(?:<div[^>]*>\s*)?([A-Za-z0-9 ./+-]{1,20}?)\s*(?:</div>)?\s*</td>',
    html)
seen = {}
for k, v in rows:
    k = k.strip()
    if k in want and k not in seen:
        seen[k] = v.strip()
for k in want:
    if k in seen:
        print(f"  {k:<18}: {seen[k]}")
if not seen:
    print("  [WARN] 没解析到字段表，手动开 scamalytics.com/ip/<IP> 看")
PY
else
  curl -s --max-time 25 -A "$UA" "https://scamalytics.com/ip/${IP}" \
    | grep -oE 'Fraud Score: *[0-9]+' | head -2 | sed 's/^/  /'
fi
echo

# ---------- 4. PTR ----------
echo "── 4/5 PTR 反解"
if [ -n "$PYBIN" ]; then
  "$PYBIN" - "$IP" <<'PY'
import socket, sys
try:
    print("  " + socket.gethostbyaddr(sys.argv[1])[0])
except Exception:
    print("  (无 PTR)")
print("  说明：住宅 IP 不一定有 PTR；整段都没有 PTR 是机房批量分配的典型特征")
PY
else
  echo "  (跳过：无 python)"
fi
echo

# ---------- 5. 出口国 ----------
echo "── 5/5 出口国交叉核对（cloudflare trace）"
curl -s -m 20 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(ip|loc|colo)=' | sed 's/^/  /'
echo

echo "── 结论 ──"
echo "  必须同时满足："
echo "   · ipinfo: asn.type=isp 且 company.type=isp"
echo "   · 第二源 ipapi.is: ASN 编号与 ipinfo 一致（不一致 = 有一家库过时，别急着付款）"
echo "   · Scamalytics: Server/Public Proxy/VPN/Tor 全 No，Connection type = dsl"
echo "  缺任何一条都不算达标；开通后必须逐项复验，别拿客服给的样品 IP 当成品。"
