> 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT

# 阶段 3-4：链式代理与 DNS 防泄漏

> 端口、密码、节点名一律用占位符。真实值只留在自己的密码管理器里。

## 一、为什么链式

- 机场节点 → 共享 IP，被大量人用过，直接当出口很脏
- 自己的住宅服务器 → 干净，但直连时跨境那段走公网国际出口，又慢又暴露真实 IP
- 链式 = 机场只管「线路」（IEPL 专线快），自己的服务器管「身份」

```
本机 → 日本节点(入口) → 美国住宅服务器(出口) → 目标
```

**「出口 IP」永远指最后一跳。** 中间是日本，但网站看到的是美国。

## 二、服务器端

执行 `bash scripts/install-ss.sh <SS_PORT> [密码]`。

三个坑：

- apt 装完会自动起一个只监听 `127.0.0.1` 的默认实例 → 必须覆盖 `/etc/shadowsocks-libev/config.json` 成 `"server": ["0.0.0.0"]`
- 密码用纯十六进制（`openssl rand -hex 16`），避开 base64 的 `+/=` 在 URI 里要转义
- 加密用 `chacha20-ietf-poly1305`

脚本会顺手做一次回环自测（服务器上起 `ss-local`，走它 curl 一次），返回正确 IP 说明服务端 OK，再去调客户端。

## 三、客户端：Clash Verge Rev

前置条件：客户端是 **Clash Verge Rev**（配置目录 `io.github.clash-verge-rev.clash-verge-rev`），内核 verge-mihomo。

核心就一件事：给出口节点加一行

```yaml
dialer-proxy: '<日本节点的精确名字>'
```

三种改法，可靠性排序：

1. **script 扩展（推荐）**：JS 里直接改 `config.proxies`，订阅更新也不丢
2. Merge 覆写
3. 界面「编辑节点」高级模式 —— ⚠️ 每次改完都可能吞掉 `dialer-proxy`

⚠️ **不要点界面的「链式代理」按钮**，已知 bug 会无差别删掉 `dialer-proxy`。

### 中间节点选日本

地理上离美西最近，延迟最低。实测日本 → 美国西岸 RTT 约 90ms。

选的时候注意名字要**逐字一致**：国旗 emoji、全角 `｜` 和半角 `|` 是完全不同的字符，手打必错，一律复制。

### 自定义节点不会自动进策略组

用「编辑节点 / prepend」加的节点只存在于 `proxies`，不在任何 `proxy-groups` 里 → 规则模式的代理页看不到它。两个出路：切「全局」模式，或在 Merge 里 `append-proxy-groups` 把它挂进组。

## 四、怎么验（唯一硬判据）

**不要看出口 IP。** 出口 IP = 服务器 IP 只证明「流量到了服务器」，不证明经过了日本。

硬判据在**服务器侧**：

```bash
# 在服务器上跑
bash scripts/check-chain.sh <SS_PORT>
```

输出应该只有中间节点 IP，**没有任何你的家宽 IP**。

失败时按这个顺序查：

1. GLOBAL 选的是不是那个出口节点（不是日本节点）
2. `dialer-proxy` 还在不在（改过节点后常丢）
3. 节点名是否逐字一致
4. 中间节点是不是死了（单节点测速）
5. 自定义节点有没有挂进策略组

## 五、DNS 防泄漏

### 泄漏长什么样

```bash
nslookup -type=TXT o-o.myaddr.l.google.com
```

回 `edns0-client-subnet 203.0.113.0/24` 这种**你自己所在地的真实子网**，就是泄露。修好后应该是出口网段。

### 关键坑

**Clash Verge 的 DNS 覆写会盖掉 profile 和脚本里的 dns。** 真正生效的是独立文件：

```
%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\dns_config.yaml
```

改 script 扩展里的 `config.dns` 或订阅 profile 都**无效**。改完必须重启 `clash-verge.exe`。

### 修法

```yaml
respect-rules: true
nameserver:
  - https://1.1.1.1/dns-query
  - https://8.8.8.8/dns-query
default-nameserver:
  - 223.5.5.5
  - 119.29.29.29
proxy-server-nameserver:
  - tls://223.5.5.5
  - tls://223.6.6.6
```

- `respect-rules: true` —— DNS 连接遵守路由，走代理
- 只留国外 DoH
- `proxy-server-nameserver` 用 **IP 型 DoT**，解析「节点域名」必须直连，IP 型免引导解析

### 代价（重要）

**「DNS 防泄漏」和「能脱离代理上网」互斥。** 只留国外 DoH 后，一切不经代理的流量都解析不了 —— 切「规则」或「直连」模式会全站打不开（所有请求 `000`）。

我用的是**全局模式**，接受这个代价。别在这台机器上试图加「某域名直连」的规则。

### 复验

```bash
bash scripts/check-dns-leak.sh
```

再在浏览器开 `ipleak.net`，DNS 列表必须全是出口国的解析器。

## 六、关 IPv6

服务器只有 IPv4，代理不了 IPv6 → 客户端必须禁掉，否则运营商 IPv6 会绕过隧道直连。

- **Windows**：禁用物理网卡的 IPv6 绑定（需要管理员）
- **手机**：APN 协议改「仅 IPv4」（部分机型把该选项锁死，改不了就只能接受）

判据：

```powershell
Get-NetRoute -AddressFamily IPv6 | ? {$_.DestinationPrefix -eq '::/0'}
```

结果应该为空或指向 TUN，**不能指向物理网卡**。

## 七、大文件下载

链式下「源站 → 美国 → 日本 → 本机」的最后一段是机场共享带宽，对大流量限速明显（实测比服务器直连慢 20 倍以上）。

解法：用订阅里的**下载专用节点**（流量倍率低的那种），保持全局模式，在「代理」页把 GLOBAL 直接选成它，下载完切回出口节点。**不要切「直连」** —— DNS 会挂。
