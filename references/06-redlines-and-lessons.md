> 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT

# 红线与踩坑时间线

## 七条红线

1. **不共享账号、不做反代** —— 一个号卖 N 个人是最快的封号方式
2. **不在本地装 Claude Code 登录自己的号** —— 一律远程 SSH 到服务器
3. **远程 SSH 前先过闸门** —— 否则真实 IP 会进服务器日志。做法不是「记得开梯子」，而是按本文末尾「SSH 直连的永久修复」配好 `ProxyCommand`，并在每次连之前跑 `scripts/ssh-guard.sh <别名>`；闸门不通过就不要连（`AGENTS.md` 第 6 节）
4. **不点 Clash 的「链式代理」按钮** —— 会静默删掉 `dialer-proxy`
5. **验链式只看服务器侧来源** —— 出口 IP 对了也可能根本没成链
6. **Pro 开通后前三天维持英文**，别立刻切中文
7. **服务器只写码，不在上面编译构建**

## 踩坑时间线（都是真事）

| 现象 | 根因 | 解法 |
|---|---|---|
| 商家说住宅 IP，实测是机房 | 宣传 ≠ 数据库字段 | 付款前跑 `check-ip-quality.sh` |
| 换了一次 IP 还是机房 | 同实例换绑，不是换产品线 | 直接问「有没有住宅产品线」 |
| 客服给的 IP 完美，实开的很差 | 测试 IP 只是样品 | 开通后逐项复验 |
| 出口 IP 对了但链路是直连 | 只看出口 IP 会误判 | 查服务器侧 `ss -tn` 来源 |
| 改了 IP 后链式消失 | 编辑节点会吞掉 `dialer-proxy` | 改完回读配置确认 |
| 切「规则」模式全站打不开 | DNS 只留国外 DoH | 保持全局模式 |
| DNS 改了不生效 | `dns_config.yaml` 覆盖了 profile | 改那个独立文件 |
| WebRTC 漏真实内网 IP | 代理类型是 HTTP | 换 Socks5 + 代理UDP |
| 谷歌注册弹出自拍验证 | 正常做即可，同一轮最多两次 | 超两次就停，隔满 24 小时再试 |
| 服务器跑 3 个 claude 卡死 | 1G 内存到顶 | 一次只留一个 |
| 额度每次打满、长期满载 | 用量曲线像机器，风控先看这个 | 每次留 5%–10% 余量，别把额度榨干 |
| 编译报 OOM | 1C1G 不是开发机 | 编译回本地 |
| 大文件下载慢 20 倍 | 链式最后一段被机场限速 | 切下载专用节点 |
| SSH 连不上 | 链路抖动 | 重试即好 |
| 真实 IP 出现在 `auth.log` | 忘开梯子 | 开梯子再 SSH；清日志是边清边漏 |
| Windows 上 Qoder/IDE 连不上 | `~/.ssh/config` 权限里有其他用户 | `icacls /inheritance:r` + 只授权自己 |
| 手机导入配置后列表不新增 | App 自己拉配置的请求被 `MATCH` 送进隧道 | **先停 VPN 再导入**，并加内网直连规则 |
| 手机报 `dns resolve failed` | 中转入口是域名，解析请求又被送进代理 | 在配置 `hosts:` 里把入口域名钉成 IP，另留一份备用订阅 |
| 手机链式看着通、实际没成链 | 又只看出口 IP 了 | 看手机侧 `ss -tn`：应只连中转入口，无直连出口服务器 |
| 手机 WebRTC 出现公网地址 | 节点缺 `udp: true` | 补上；若仍拿不到公网候选属正常（回程受限，不影响安全） |
| 指纹浏览器「系统时区」和「IP 时区」差几小时 | 时区用了「基于 IP」，AdsPower 的库按美国东部兜底 | 改「自定义 `America/Los_Angeles`」，关环境重开再验 |
| 地理位置显示无定位 | 选了「自定义」但经纬度空 | 要么退回「基于 IP」，要么填真实城市坐标 |
| 关了 IPv6 仍有 `240e:` 地址 | 那是 IMS APN 分配的，供 VoLTE 用 | **不要动 IMS**，只看应用层 `curl -6` 是否为空 |
| 「不开梯子就断网」没生效 | 部分 ROM 不执行 `always_on_vpn_lockdown` | 别依赖，改为封 App 后台 + 行为纪律 |
| 重启后手机没网 | 客户端没被系统拉起（后台管理杀了） | 打开客户端点启动；去系统里给自启动权限 |

## 关于「证明没被封」

- 能自证的只有：`claude-safe -p 'OK'` 返回、账号 Settings 里会话位置 = 服务器所在城市
- 不能自证的是「这套配置导致了不封」—— n=2、无对照组，因果关系无法验证

对外表述建议：

> 我两个号从 2026-10-08 注册起一直可用，做法是这一套。这是个人经验，不是保证。

不要说：

> 按这个做就不会被封。

## 隐私纪律

写文档、发截图、贴日志时，以下内容一律不出现：

- 服务器 IP、SSH 端口
- Claude 账号邮箱、用户名、Organization ID
- `sk-ant-` 开头的 token
- 机场订阅链接、节点名、订阅 uid
- 家宽真实 IP、家庭所在地
- KYC 证件信息

## SSH 直连的永久修复：ProxyCommand（2026-11 补）

**问题**：Windows 的 OpenSSH **不读系统的「系统代理」设置**。只开 Clash 的「系统代理」而不开 TUN 时，浏览器走了代理，`ssh` 却从你家宽真实 IP 直连服务器 —— 不报错、也不慢，但真实 IP 已经写进了服务器日志。

**修法**：在 `~/.ssh/config` 的服务器条目里加一行 `ProxyCommand`，SSH 以后永远走本地代理，不再依赖 TUN：

> 一条命令：`bash scripts/ensure-ssh-proxy.sh <别名> 127.0.0.1:7897`（幂等、自动备份、`ssh -G` 校验）。
> 之后每次连之前跑 `bash scripts/ssh-guard.sh <别名> --live`。


```sshconfig
Host <alias>
    HostName <服务器IP>
    Port <SSH端口>
    User root
    IdentityFile ~/.ssh/id_ed25519_xxx
    IdentitiesOnly yes
    ProxyCommand connect -H 127.0.0.1:7897 %h %p
```

- `connect` 是 **Git for Windows 自带**的小工具，路径 `C:\Program Files\Git\mingw64\bin\connect.exe`；Git Bash 里 `which connect` 能查到就能用，不用另装
- `-H` = 用 HTTP CONNECT 方式穿代理；`%h %p` 是 SSH 的占位符，替换成 HostName / Port；`7897` 是 Clash Verge Rev 默认的 HTTP 代理端口（混入端口）

**代价（用之前要知道）**：

| 情况 | 表现 |
|---|---|
| Clash 开着、7897 在听 | 正常连，不依赖 TUN |
| Clash 完全退出，7897 不在听 | **fail-closed**：`ssh` 直接失败（`Connection closed by UNKNOWN port 65535`），不会悄悄退回直连 |

这条「不会悄悄退回直连」是**故意**的：宁可连不上，也不要不知不觉漏真实 IP。所以：
- 不要同时保留一条直连别名当作「备用」——真出问题时你会下意识用它，一次就把真实 IP 写进 `auth.log`
- 用户说「关梯子」时，通常只关了 TUN / 系统代理，**7897 往往还在监听**，SSH 照通且不泄漏。判断方法：`Test-NetConnection 127.0.0.1 -Port 7897`（PowerShell）或 Git Bash 里 `curl -s -o /dev/null -w '%{http_code}' -x http://127.0.0.1:7897 https://www.cloudflare.com/cdn-cgi/trace`

**验证配好了**（两条都做）：

```bash
ssh <alias> 'echo $SSH_CONNECTION'
# 第一段应该是代理出口（美国），不是你家宽 IP

ssh <alias> "sudo journalctl -u ssh --since '1 hour ago' | grep Accepted"
# 来源 IP 应该是代理出口；如果出现家宽 IP，说明还在直连
```
