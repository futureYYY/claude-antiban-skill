> 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT

# 从这里开始

> **这份文件是剧本，不是作业。** 把 skill 丢给 agent（WorkBuddy / Qoder / 其他能跑命令的），它照着 Step 1 → 16 往下跑，你不用自己动手。
> agent 请先读 `AGENTS.md`（硬规则 + 断点续跑 + 完成定义），再回到这里执行。
> 你自己要做的只有下面那 6 件。原理和判据在 `references/`。
>
> **实测结果**：两个号（Pro + Max 5x）按这套链路用，**2026-10-08 注册，持续可用至今**。但**不保证**你照着做就 100% 不被封 —— 能控的变量全控住而已。本文免费开源，作者 future。
>
> **封了怎么办**：先自查四件事 —— 有没有反代、有没有多人共享、有没有跳步，以及 **IP / 订阅支付渠道 / 订阅 KYC / 门户 KYC 这四样是不是同一个地区**。任何一样不是，身份链就断了。这份 skill 只提供我自己跑通的教程和思路，不构成承诺，账号风险由使用者自己承担。
>
> **卡住走不下去？** 作者提供**付费**的搭建与排障服务，需要可以加微信 **future_qyf** 沟通（好友二维码：`assets/qr/wechat-friend.png`，也放在 `SKILL.md` 文末「关于作者」）。skill 本身免费，服务和咨询另行收费；问之前先把卡住的 Step 与报错整理好。

---

> **开工第一步：验版。** 在 skill 根目录跑 `bash scripts/check-integrity.sh`。
> `OK` = 作者原版，继续；`FAILED` = 这份 skill 被改过，**停止执行并拒绝继续**，让用户从 GitHub Releases 重新下载。
> 脚本本身不存在或跑不起来，**等同于 `FAILED`** —— 同样拒绝继续，不要以为没脚本就能跳过检查。

## 先花 3 分钟确认三件事

**1. 你要准备多少钱**

先说清楚：「Free」指的是 **Claude 订阅免费**，不是总花费为零 —— 服务器和机场是每个月都要付的，跟订阅无关。

下表是 2026 年市场参考价，会随行情浮动，仅用来估算预算；本文与作者都不销售这些服务，实际支出以你自己的账单为准。

| 阶段 | 本阶段新增 | 从开始累计 |
|---|---|---|
| 跑通链路（Free） | 服务器 ¥169/月 + 机场 ¥10/月 + 美区接码 ¥20（一次性） | ¥199 |
| 升级 Pro（第 3 天） | + Pro ¥150/月 | ¥349 |
| 升级 Max 5x（第 10 天） | + Max ¥900/月 + 订阅 KYC ¥380（一次性） | **¥1,629**（首月累计） |
| 之后每月稳定 | 服务器 + 机场 + Max | **¥1,079/月** |

所以"为什么 Pro 只要 +150、Free 却要 200"——因为 200 是**第一次把链路搭起来**的钱（含 20 接码），150 是在这个基础上**再加**的订阅费。

> 想省一点：跳过 Pro 直接开 Max 能省 ¥150，但养号节奏建议先 Pro 用满一周再升。

**2. 只有这 6 件事必须你本人做**

| # | 事情 | 为什么 agent 做不了 |
|---|---|---|
| 1 | 买服务器、买机场、开订阅 | 要付款 |
| 2 | 谷歌账号手机接码 | 要一个真实号码 |
| 3 | 邮箱里点验证（**右键复制链接**） | 邮箱是你的私有账户 |
| 4 | KYC 证件 + 真机自拍 | 要本人身份 |
| 5 | UAC 弹窗点「是」 | 系统要求人确认 |
| 6 | 浏览器里点 Authorize / 首次输一次 root 密码 | 一次性交互 |

**其余全部交给 agent**：验 IP、装 shadowsocks、加固服务器、配链式、改 DNS、关 IPv6、建 AdsPower 环境、装 Claude Code、逐项验收。它做不了的会按「卡在 Step N / 现状 / 判定 / 需要你 / 拿到之后我会」告诉你，不会只丢一句「请你去配一下」。

**3. 你的电脑需要什么**

- Windows 10/11
- 一个能跑命令的 agent（WorkBuddy / Qoder / 其他）
- 装 Clash Verge Rev 和 AdsPower 的权限

---

## 第 1 部分 · 服务器（约 40 分钟）

### Step 1 · 买服务器

**做什么**：买一台美国**静态住宅 IP** 的 VPS。

本文实测用的是一条「美国静态住宅 IP VDS」产品线（基础版约 ¥169/月，1 核 / 1 GB 内存 / 20 GB 盘 / 100 Mbps 双向 / 月流量 3000 GB，Ubuntu 22.04）。商家会变、价格会变，**认产品线特征，不必认某一家**。

> ⚠️ 不是他家那些写着「双 ISP 住宅 IP」的普通 4837 / 9929 产品线 —— 那两个实测下来 IP 是机房段（Cogent / NTT），宣传和实测对不上。**认产品线，不认宣传语。**

**多久**：10 分钟
**你会看到**：面板里多一行实例，上面有 **IP、root 密码、SSH 端口**（不一定是 22）。有的商家会发邮件。
**马上做**：把这三样记进密码管理器，别截图发群里。

**卡住看**：`references/01-server-and-ip.md` 第一节

---

### Step 2 · 验 IP（付款后 48 小时内必须做）

**做什么**：确认买到的是不是真住宅 IP。

```bash
bash scripts/check-ip-quality.sh <你拿到的IP>
```

**多久**：2 分钟
**你会看到**：一段报告。达标长这样 ——

```
→ 双ISP ✅
Fraud Score   : 0 / 100
Server        : No
Public Proxy  : No
Connection type: dsl
```

**不达标怎么办**：带着截图找客服换，话术在 `references/01` 第五节。很多商家有 48 小时退款窗口，过了就只能认。
**卡住看**：`references/01-server-and-ip.md` 第二、四、五节

---

### Step 3 · 买机场（梯子）

**做什么**：买一份能用的机场订阅，拿到一条 **Clash 格式的订阅链接**。

便宜的几块到十几块一个月都有，看你要多少流量。**中间节点选日本**（离美西最近，延迟最低）。

**多久**：10 分钟
**你会看到**：一条 `https://...` 开头的订阅 URL，或者二维码。

---

### Step 4 · 装 Clash Verge Rev

**做什么**：装客户端并导入订阅。

1. 装 **Clash Verge Rev**（不是旧版 Clash Verge）
2. 「订阅」页 → 导入刚才那条 URL
3. 「设置」里打开 **TUN 模式**，同时把 **系统代理** 也打开
4. 「代理」页选一个日本节点
5. 浏览器打开 `ipinfo.io`，确认显示日本

> **TUN 模式是后面全流程的前提，不是可选项。** 只开「系统代理」不够 —— Windows 的 OpenSSH 不读系统代理，`ssh` 依然会从你的真实 IP 直连服务器。所以从这一步起，TUN 就一直开着。

**多久**：15 分钟
**你会看到**：浏览器能打开 Google 了。

---

## 第 2 部分 · 网络（约 50 分钟）

### Step 5 · SSH 连上服务器

**做什么**：从本机连到那台美国服务器。

Windows 上打开 Git Bash 或 PowerShell：

```bash
ssh -p <SSH端口> root@<IP>
```

第一次会问 `yes/no`，输 `yes`；然后输密码（**输入时屏幕不显示，是正常的**）。

**多久**：5 分钟
**你会看到**：提示符变成 `root@xxxx:~#`，说明你进去了。

**连上之后，第一件事（必做，不是建议）**：把 `ProxyCommand` 钉进 `~/.ssh/config` 的别名条目。做完之后 SSH 永远走本地代理，不依赖 TUN，也不会在你「忘了开梯子」的时候从家宽直连 —— 而且代理一关就**直接连不上**（fail-closed），不会悄悄退回直连。

一条命令搞定（幂等，会先备份、再用 `ssh -G` 校验）：

```bash
bash scripts/ensure-ssh-proxy.sh <alias> 127.0.0.1:7897
ssh -G <alias> | grep -i "^proxycommand"   # 应输出 connect -H 127.0.0.1:7897 %h %p
```

手工写也行，等价于：

```sshconfig
# ~/.ssh/config
Host <alias>
    HostName <IP>
    Port <SSH端口>
    User root
    IdentityFile ~/.ssh/id_ed25519_xxx
    IdentitiesOnly yes
    ProxyCommand connect -H 127.0.0.1:7897 %h %p
```

之后一律用 `ssh <alias>`，并且**每次连之前先过闸门**：

```bash
bash scripts/ssh-guard.sh <alias>          # 静态 + 端口
bash scripts/ssh-guard.sh <alias> --live   # 再验一次服务器看到的来源
```

`connect` 是 Git for Windows 自带的；配好后 Clash 完全退出会直接连不上（故意的，见 `references/06`「SSH 直连的永久修复：ProxyCommand」）。

**判据**：`ssh -G <alias>` 里有那行 `ProxyCommand`；把 Clash 退出后 `ssh <alias>` 应**直接失败**而不是连上；`--live` 通过。

**卡住看**：`references/06` 最后一条（Windows 权限问题）

---

### Step 6 · 在服务器上装出口

**做什么**：把这台机器变成你的代理出口。

把 `scripts/` 里的文件传上去，或者直接在服务器上手工执行 `install-ss.sh` 的内容：

```bash
bash install-ss.sh <SS端口> [密码]
```

**多久**：5 分钟
**你会看到**：
- `active` + 端口在 LISTEN
- 一行「经本地 socks 的出口 IP: x.x.x.x」，这个 IP 应该就是你的服务器 IP
- 最后打印一条 `ss://...` 的节点 URI

**没看到那个 IP 就停**，别往下走。
**卡住看**：`references/02` 第二节

---

### Step 7 · 加固服务器

**做什么**：时区、swap、防火墙、仅密钥登录、关 IPv6。

```bash
bash harden-server.sh <SSH端口> <SS端口> America/Los_Angeles
```

**多久**：5 分钟
**你会看到**：一段段的进度，最后提示复验命令。
**注意**：跑完**立刻另开一个终端再连一次**，确认还能进；当前窗口别关。

**卡住看**：`references/01` 第七节

---

### Step 8 · 配链式代理（最容易卡的一步）

**做什么**：让流量走「本机 → 日本节点 → 美国服务器」。

> **交给 agent 时**：让它直接改配置文件（`clash-verge.yaml` 或生效的 script 扩展），再用命名段热重载，不用你点 GUI。下面是手动路径。

1. 打开 Clash Verge Rev → 左侧「**订阅**」页
2. **右键**那张订阅卡片 —— 注意是右键卡片，不是点进去，也不是顶部那个导入框
3. 选「**编辑节点**」
4. 点右上角「**高级**」切到 YAML
5. 在 `prepend:` 下面加一段：

```yaml
prepend:
  - name: 'us-residential'
    type: ss
    server: <你的服务器IP>
    port: <SS端口>
    cipher: chacha20-ietf-poly1305
    password: '<SS密码>'
    udp: true
    dialer-proxy: '<日本节点的名字，右键复制，别手打>'
```

6. 保存
7. 去「**代理**」页，顶部切「**全局**」，点选 `us-residential` 让它高亮
8. 完全退出 clash-verge.exe 再打开

> ⚠️ 从头到尾**不要点界面上那个「链式代理」按钮**，它会把 `dialer-proxy` 删掉。

**多久**：15 分钟
**你会看到**：浏览器 `ipinfo.io` 显示的是**美国**（不是日本）。
**但这不算验完** —— 接着做下一步。

**卡住看**：`references/02` 第三、四节

---

### Step 9 · 验链式到底成没成

**做什么**：在**服务器上**看连接来源。

```bash
ssh -p <SSH端口> root@<IP> "bash check-chain.sh <SS端口>"
```

**多久**：2 分钟
**你会看到**：一张来源统计表。
- 来源全是**日本 IP** → ✅ 成链了
- 出现**你家宽 IP** → ❌ 退化成直连了，回 Step 8 查 `dialer-proxy` 还在不在

> 出口 IP 显示美国 ≠ 链式生效。唯一的硬证据是这张表。

**卡住看**：`references/02` 第四节

---

### Step 10 · DNS 防泄漏

**做什么**：把 DNS 也塞进代理，别让你的解析器暴露位置。

先查：

```bash
bash scripts/check-dns-leak.sh
```

如果回显的子网是**你自己所在地**的，就是漏了。修法：

> **交给 agent 时**：它直接改 `dns_config.yaml` 并重启客户端，你不用动手。下面是手动路径。

1. 找 `%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\dns_config.yaml`
2. 改成 `references/02` 第五节给的那四段（`respect-rules: true` + 只留国外 DoH）
3. 完全退出 clash-verge.exe 再打开
4. 再跑一次 `check-dns-leak.sh`，ECS 子网应该变成你的出口网段了

> 改 script 扩展或订阅 profile 里的 dns **没用**，Clash Verge 的 DNS 覆写会盖掉它们，只有这个文件算数。

**多久**：15 分钟
**你会看到**：浏览器开 `ipleak.net`，DNS 那一栏全是美国解析器。

**代价**：改完之后切「规则」或「直连」模式会全站打不开。**保持全局模式**。

---

### Step 11 · 关掉 IPv6

**做什么**：你的服务器只有 IPv4，IPv6 会绕过隧道直接出去。

Windows（管理员 PowerShell）：

```powershell
Get-NetAdapter | ? { $_.Status -eq 'Up' -and ($_.InterfaceDescription -like 'Intel*' -or $_.InterfaceDescription -like 'Realtek*') } | Disable-NetAdapterBinding -ComponentID ms_tcpip6
```

**多久**：5 分钟
**你会看到**：`Get-NetRoute -AddressFamily IPv6` 里不再有指向物理网卡的 `::/0`。

---

## 第 3 部分 · 浏览器（约 20 分钟）

### Step 12 · 建一个 AdsPower 环境

**做什么**：让浏览器也「住」在美国。

> **交给 agent 时**：让它调 AdsPower 本地 API（`127.0.0.1:50325`，`/api/v1/user/create`）直接建，不用你手点。
> 下面是 API 不通时你自己点的路径。

1. 打开 AdsPower → 「新建环境」
2. **基础设置**：名称随便起（别叫「Claude 账号」），浏览器选 `SunBrowser`，操作系统选 Windows
3. **代理信息**：类型 `Socks5`，主机 `127.0.0.1`，端口 `7897`，点「检查代理」
   - 这一步**必须点**，要看到返回的 IP 是你的服务器 IP 才算通
4. 切到 **「指纹配置」** 页，按 `references/03` 那张表逐项填
   - 最关键的三个：WebRTC = **代理UDP**、时区 = **基于 IP**、语言 = **基于 IP**
5. 保存 → 打开环境

**多久**：20 分钟
**你会看到**：浏览器打开后，`browserscan.net` 显示**真实性 100%**，`browserleaks.com/webrtc` 显示 `No Leak`。

**卡住看**：`references/03-browser-fingerprint.md`

---

## 第 4 部分 · 账号（约 3 天）

> **买的是成品号？** 分两种情况，别混：
>
> **① 订阅号（Pro / Max）** —— 跳过 Step 13、Step 14，也不需要美区手机号接码、不需要 3 天养号：
>
> 1. **当天**：在已配好的 AdsPower 环境里正常登录、正常使用，**先别改密码**
> 2. **满 24 小时后（第二天）**：改密码 → 换绑恢复邮箱 → 用新密码重新登录一次。**这步不能省**，不改密码，原持有人随时能登回来把号拿走
> 3. **同一天**：打开 Claude → **Settings → Account → 「Where you're logged in」**，把不是你的设备全部登出（或直接点 `Log out of all devices`），再用自己的设备重新登录
> 4. 核对套餐与到期时间
> 5. 之后低频用 2–3 天再上量；**平时别把额度一次用满，留 5%–10% 余量**
>
> **② 免费号（Free）** —— 只跳过「注册」：账号名与资料卖家已经设好，不用你重新命名、也不用再接码。**养号流程照走**：D0 起英文使用 3 天 → 开 Pro → Pro 第 2 天再切中文；免费额度下可以一直正常提问，把这段时间当养号期。
>
> 两种情况，环境侧自查一项都不能少（出口 IP / DNS / IPv6 / 指纹）。

### Step 13 · 注册谷歌账号

**做什么**：注册一个谷歌账号，用来注册 Claude。

**直接在 AdsPower 环境里注册就行** —— 我这两个号的谷歌账号都是从指纹浏览器里注册出来的，全程没离开过那个环境。好处是 IP / 时区 / 语言从第一步就是一致的。

需要美区手机号接码。

**如果中途弹出「自拍 / 活体验证」**：自己正常认证就行，不用找人帮忙。同一轮最多试两次；**超过两次就停**，隔满整整 24 小时再试 —— 反复点重试只会让风控等级越试越高。

**多久**：20 分钟
**你会看到**：能正常登录 Gmail。

---

### Step 14 · 注册 Claude（D0）

**做什么**：用**已经配好的 AdsPower 环境**打开 `claude.ai`，注册。

- 注册资料（姓名、生日、地区）四者自洽，记住这一套，以后找回账号会问
- **全程英文**，别一上来就中文

### 验证邮件：右键复制链接，不要左键点

注册完 Claude 会发验证邮件。那个按钮是**带追踪的跳转链接**，在邮件里直接点会用「当时那个浏览器」的 IP 去打开。

1. 在邮件里找到验证按钮 → **右键 → 复制链接地址**
2. 切到 AdsPower 环境 → 粘进地址栏 → 打开
3. 不要用本机默认 Chrome，不要用手机

> 另外很多邮箱客户端会**自动加载邮件图片**，那是追踪像素，你没点它就先报了一次 IP。优先用**网页版邮箱**并在同一个指纹环境里开，或关掉「自动加载远程图片」。

**多久**：10 分钟
**你会看到**：进到对话界面，能用 Free 额度提问。

### 养号节奏（照做）

| 时间 | 做什么 |
|---|---|
| D0 ~ D3 | 每天用**英文**问几个问题，别切中文 |
| D3 | 开 Pro（¥150） |
| D4 | 才开始用中文 |
| D4 | 用同一个环境注册第二个谷歌号 → 第二个 Claude 号 |
| D4 ~ D7 | 第二个号同样 Free + 英文 3 天 → 开 Pro → 第 2 天切中文 |
| D10 左右 | 第一个号升 Max 5x（Pro 已用满一周）→ 过**订阅 KYC** |

> **两种 KYC 不是一回事**：D10 弹的是**订阅 KYC**，过的是支付关。2026-11-12 新政后还有**门户 KYC**（Portal），登录后任意时刻可能弹，与《支持地区政策》绑定，**通过也不等于保住账号**。两者区别、六种触发条件、以及「四样对齐」的做法见 `references/04-account-and-payment.md` 第五节。

**为什么这么慢**：不是因为"中文会被封" —— 养号结束后全程中文没有任何问题。前三天用英文，只是不想让刚注册的号第一天就出现「美国 IP + 中文账号」这么突兀的组合。**语言不是判定维度，行为连续性才是。**

**卡住看**：`references/04-account-and-payment.md`

---

## 第 5 部分 · Claude Code（约 40 分钟）

### Step 15 · 在服务器上装并登录

**做什么**：让服务器上的 Claude Code 用你的订阅。

```bash
# 装（不需要 Node）
curl -fsSL https://claude.ai/install.sh | bash
ln -sf /root/.local/bin/claude /usr/local/bin/claude

# 借 tmux 跑登录
tmux new-session -d -s clogin -x 220 -y 50 'claude setup-token; exec bash'

# 抓授权链接
tmux capture-pane -pt clogin -S -80 | tr -d '\n' | grep -oE 'https://claude.com/cai/oauth/authorize[^[:space:]]*'
```

**然后是最容易错的一步**：那条链接**不要在本机默认浏览器里打开**，要：

1. 打开 **AdsPower 那个美国环境**（先看一眼 `ipinfo.io` 是不是美国）
2. 把链接**粘进地址栏**，回车
3. 登录要授权的 Claude 账号 → 点 **Authorize**
4. 页面上会给一段 code（或一条回调 URL）→ **复制它**
5. 回终端：

```bash
tmux send-keys -t clogin '<粘 code>' Enter
tmux send-keys -t clogin Enter        # 有时候要补这一次，别漏
```

然后把 token 存下来（`setup-token` 不会自动存）：

```bash
mkdir -p /root/.claude && chmod 700 /root/.claude
echo '<token>' > /root/.claude/oauth_token && chmod 600 /root/.claude/oauth_token
```

**多久**：20 分钟
**你会看到**：一条 `sk-ant-oat01-` 开头的 token。**不要截图外发。**

**卡住看**：`references/05-claude-code-remote.md` 第二节

---

### Step 16 · 装两个启动封装并验收

**做什么**：把 `scripts/claude-safe` 和 `scripts/cc` 传到 `/usr/local/bin/`，`chmod 755`。

验收：

```bash
ssh -p <SSH端口> root@<IP> "claude-safe -p 'Reply with exactly: OK'"
```

**多久**：10 分钟
**你会看到**：`OK`。看到这个，整条链路就通了。

之后日常用法：

| 想做什么 | 命令 |
|---|---|
| 一次性问一句 | `ssh <alias> "claude-safe -p '<问题>'"` |
| 进交互会话 | `ssh -t <alias> "cc"` |
| 让 agent 代跑 | 把需求给 WorkBuddy / Qoder，让它 SSH 过去执行 |

---

### Step 17 · 手机端（可选）

**做什么**：把同一套链搬上手机，让手机访问 Claude 时也是美国出口。

**先说边界**：真机没有指纹浏览器的隔离能力，机型、序列号改不了，**只能一号一机**。

**完成判据**（五条全过）：

1. 手机上 `ss -tn` 只看到连向**中转入口**，没有一条直连出口服务器
2. 出口 IP = 你的服务器 IP
3. `curl -6 https://api64.ipify.org` 返回空
4. 解析器显示出口国
5. WebRTC 检测页只出现 `172.19.x` 这类私有地址

**最容易卡的三处**：

| 现象 | 原因 |
|---|---|
| 导入后列表没新增 | VPN 还开着，App 拉配置的请求被 `MATCH` 送进了隧道 → **先停 VPN 再导入** |
| `dns resolve failed` | 中转入口是域名，解析请求又被送进代理 → 在配置 `hosts:` 里把入口域名钉成 IP |
| 删配置后突然断网 | 删到了正在运行的那份 |

**三条别踩**：别动 IMS APN（影响电话短信）；别为了检测页好看把 UDP 改成直连；别指望「不开梯子就断网」——部分 ROM 不执行。

**多久**：40 分钟
**细节**：`references/09-mobile.md`

---

## 每次用 Claude Code 之前，先过这三条

**不是可选项。** 漏一条不会有任何报错，只会悄悄把真实 IP 写进服务器日志。

- [ ] **TUN 模式开着**（Clash Verge Rev「设置」页，不是只开系统代理）
- [ ] **GLOBAL 选的是 `us-residential`**（你的美国节点，不是日本节点）
- [ ] **出口真的是美国**：`curl -s -x http://127.0.0.1:7897 https://www.cloudflare.com/cdn-cgi/trace` → 看到 `loc=US`

### 忘开梯子会怎样

不会报错，一切照常：

| 项 | 实际表现 |
|---|---|
| SSH | 正常连上，可能稍慢、抖动多一些 |
| `claude-safe -p "..."` | 正常返回，Claude 正常干活 |
| 唯一代价 | 这条连接的真实 IP 写进了服务器 `auth.log` / `wtmp`，`who` / `last` 也看得到 |

所以「能用」和「没留痕」是两回事。发现忘开了：先把梯子打开，再决定要不要清日志 —— 但**徒手清日志是边清边漏**，每连一次又写一条，根治还是「开梯子再 SSH」。

---

## 跑通之后 · 每周做一次体检

链路不会报错地坏掉 —— 机场换节点、订阅到期、Clash 更新重置配置、服务器重启后服务没起来，表现都是「**照常能用，但已经在裸奔**」。所以每周跑一次：

```bash
bash scripts/weekly-check.sh
```

它会依次查四件事：

| # | 查什么 | 不对的样子 |
|---|---|---|
| 1 | 出口国家 | 不是 `US` |
| 2 | DNS 有没有漏 | ECS 子网是你本地网段 |
| 3 | IPv6 路由 | 又出现指向物理网卡的 `::/0` |
| 4 | **服务器侧链式来源** | 出现你的家宽 IP |

最后再补一句验收：

```bash
ssh <alias> "claude-safe -p 'Reply with exactly: OK'"
```

四项全过 + 返回 `OK`，这周就算安全。

---

## 常见卡点速查

| 你现在看到 | 去这里 |
|---|---|
| 商家说住宅，实测是机房 | `references/01` 四、五节 |
| `ipinfo.io` 显示日本不是美国 | 没选中出口节点，回 Step 8 |
| 出口是美国，但 `check-chain.sh` 里有你家宽 IP | `dialer-proxy` 丢了，回 Step 8 |
| 切了「规则」模式全站打不开 | DNS 只留国外 DoH，切回全局 |
| DNS 改了不生效 | 改错文件了，要改 `dns_config.yaml` |
| WebRTC 漏内网 IP | 代理类型用了 HTTP，改 Socks5 + 代理UDP |
| 谷歌注册弹出自拍 | 正常做即可，同一轮最多两次 | 超两次就停，隔满 24 小时再试 |
| `claude` 报 OOM 或卡死 | 1G 内存，同时跑超过 3 个了 |
| 服务器编译爆内存 | 服务器只写码，编译回本地 |
| npm/curl 下载极慢 | 链式最后一段被机场限速，不是服务器问题 |
| 手机导入配置后没新增 | VPN 没停，见 `references/09` 第 2 节 |
| 手机报 `dns resolve failed` | 入口是域名，配置里用 `hosts:` 钉 IP |
| 手机 WebRTC 显示公网地址 | 节点缺 `udp: true` |
| 手机删配置后断网 | 删到了运行中的那份 |
| 手机重启后没网 / 或有网也能上 | 断网锁定不可靠，见 `references/09` 第 6 节 |
| 检测页说「系统时区 ≠ IP 时区」 | 时区别用「基于 IP」，改自定义 `America/Los_Angeles`，见 `references/03` |
| 指纹浏览器显示「无定位」 | 地理位置选了自定义但经纬度空，退回「基于 IP」或填真实坐标 |
| `claude: command not found` | `ln -sf /root/.local/bin/claude /usr/local/bin/claude` |

完整 16 条在 `references/06-redlines-and-lessons.md`。

---

## 全部做完，你手里应该有

- [ ] 一台验过的住宅 IP 服务器，只有 2 个端口对外开放，仅密钥登录
- [ ] 链式代理生效，服务器侧看到的来源是日本节点
- [ ] DNS 不漏，IPv6 已关
- [ ] AdsPower 环境真实性 100%
- [ ] 一个养了 3 天以上的 Claude 账号
- [ ] `claude-safe -p 'Reply with exactly: OK'` 返回 `OK`

七项全打勾，就算跑通了。
