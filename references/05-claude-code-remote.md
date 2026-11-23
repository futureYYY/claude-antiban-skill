> 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT

> **本机不装 Claude Code**：用 Qoder 等 agent 下发指令，经 SSH 到服务器上的 Claude 执行；本机只保留编辑器与浏览器。

# 阶段 8：远程用 Claude Code

> 本文不含服务器 IP、SSH 端口、token 内容。示例一律用 `<alias>` / `<VPS_IP>`。

## 一、为什么不在本地装

本地装 Claude Code 并用订阅登录，OAuth 授权请求来自你自己的浏览器，出口是你的真实 IP。

服务器方案里，请求源**永远是服务器 IP**，和本地梯子开不开无关。

另外 `claude setup-token` 出来的是 **1 年期 token**，可以只放在服务器上，本机不留任何登录态。

## 二、登录：链接必须拿到指纹浏览器里打开

整个流程六步，缺一步都不行：

**1）服务器上装**

```bash
curl -fsSL https://claude.ai/install.sh | bash
ln -sf /root/.local/bin/claude /usr/local/bin/claude
```

**2）借 tmux 起登录**

```bash
tmux new-session -d -s clogin -x 220 -y 50 'claude setup-token; exec bash'
```

**3）把授权链接抓出来**

```bash
tmux capture-pane -pt clogin -S -80 | tr -d '\n' \
  | grep -oE 'https://claude.com/cai/oauth/authorize[^[:space:]]*'
```

**4）把整条链接复制到本机指纹浏览器的地址栏打开**

- 必须是 **AdsPower 那个环境**，不是本机默认 Chrome，不是手机
- 打开前确认那个环境能通（先开一次 `ipinfo.io` 看是不是美国）
- 登录要授权的那个 Claude 账号 → 点 **Authorize**

**5）页面上会给一段 code（或一条回调 URL）→ 复制它**

**6）回终端送进去**

```bash
tmux send-keys -t clogin '<粘 code>' Enter
tmux send-keys -t clogin Enter        # 必须补这一次
```

⚠️ 两个坑：

- 第一次 `send-keys ... Enter` 经常不提交（终端已经把 code 回显成 `***` 了，但没按下去）→ **单独再补一次 Enter**
- `setup-token` **不会**自动存凭证，跑完没有 `~/.claude/.credentials.json`，要手工挂

## 三、token 落盘三层

```bash
mkdir -p /root/.claude && chmod 700 /root/.claude
echo '<token>' > /root/.claude/oauth_token && chmod 600 /root/.claude/oauth_token
```

再补两处，保证交互 shell 和非交互 shell 都能取到：

1. `/root/.claude/settings.json` 里的 `env.CLAUDE_CODE_OAUTH_TOKEN`
2. `~/.bashrc` 与 `/etc/profile.d/*.sh` 里导出

token 是 `sk-ant-oat01-` 开头、**1 年期**。**不截图、不贴对话、不进任何仓库。**

## 四、两个启动封装

装到 `/usr/local/bin/`，`chmod 755`：

- **`claude-safe`**：先 `unset SSH_CONNECTION SSH_CLIENT SSH_TTY`，再挂 token，再 `exec claude`
- **`cc`**：在 tmux 里跑 `claude-safe`，断 SSH 任务不死

**完成判据**：

```bash
ssh <alias> "claude-safe -p 'Reply with exactly: OK'"   # 返回 OK
```

## 五、用 agent 接力（WorkBuddy / Qoder / 其他）

```
你 → 本机 agent → SSH → 服务器 claude-safe -p "<你的需求>"
                        ↓
                   Claude 的原话
                        ↑
你 ← 本机 agent ←──────┘（原样带回）
```

两种模式：

- **一次性任务**：`ssh <alias> "claude-safe -p '<需求>'"`，出结果就结束
- **长任务 / 多轮**：tmux 里起会话，agent 用 `tmux send-keys` 送指令、`capture-pane` 取回复

纪律：**agent 只搬运，不改写。** 把 Claude 的原话带回给用户，不要自己总结成「它说可以了」。

## 六、每次开工前，先查这三条

这不是可选项 —— 少一条就会把真实 IP 写进服务器日志。

| # | 检查什么 | 怎么查 |
|---|---|---|
| 1 | **TUN 模式是开的** | Clash Verge Rev「设置」页，TUN 开关必须是开；只开「系统代理」**不算** |
| 2 | **GLOBAL 选的是出口节点** | 「代理」页顶部切「全局」，高亮的必须是 `us-residential`（你的美国节点），不是日本节点 |
| 3 | **出口真的是美国** | `curl -s -x http://127.0.0.1:7897 https://www.cloudflare.com/cdn-cgi/trace` → 看 `loc=US` |

### 为什么必须是 TUN，不能只开系统代理

**Windows 的 OpenSSH 不读系统代理设置。** 关掉 TUN 只开「系统代理」时，浏览器走代理了，但 `ssh` 会**从你的真实 IP 直连**服务器 —— 你以为开着梯子，其实日志里已经是真身了。

要在不开 TUN 的情况下也走代理，必须给 `~/.ssh/config` 加 `ProxyCommand`（一条命令：`bash scripts/ensure-ssh-proxy.sh <别名> 127.0.0.1:7897`；每次连之前跑 `bash scripts/ssh-guard.sh <别名> --live`。完整说明见 `references/06`「SSH 直连的永久修复：ProxyCommand」）：

```sshconfig
Host <alias>
    # 其余照常：HostName / Port / User / IdentityFile
    ProxyCommand connect -H 127.0.0.1:7897 %h %p
```

`connect` 是 Git for Windows 自带的（`which connect` 能查到就能用），不用另装。加了以后 SSH **永远走代理、不再直连**：Clash 完全退出时会直接连不上（fail-closed）—— 这是故意的，宁可连不上，也不要悄悄漏真实 IP。**新手直接开 TUN 最省事，但配上这行更稳。**

## 七、忘开梯子会怎样（实测）

这一条很多人以为是「马上报错」，其实不是：

| 项 | 实际表现 |
|---|---|
| SSH | **正常连上**，可能稍慢、链路抖动多一些 |
| `claude-safe -p "..."` | **正常返回**，Claude 正常干活 |
| 唯一的代价 | 这条连接的真实 IP 写进了服务器 `auth.log` / `wtmp`，`who` / `last` 里也看得到 |

所以「能用」和「没留痕」是两回事 —— 忘开梯子不会有任何报错提醒你。

**多一层的风险**：服务器上的 Claude Code 是 root，它如果执行 `who` / `last` / `cat /var/log/auth.log`，就能读到你的真实 IP，然后写进上下文发出去。

**处理原则**：发现忘开了，先把梯子打开，再决定要不要清日志。**徒手清日志是边清边漏**（每连一次又写一条），根治还是「开梯子再 SSH」。

## 八、远程使用必须注意

1. `claude-safe` 里的 unset 只是兜底，堵不掉「主动执行 `who`」这条路。
2. **1G 内存上限**：一个 claude 进程 140~250 MB，1G 机器**最多 3 个**，第 4 个必爆 swap。
3. **周额度与网页版共用**，不是独立池。
4. 服务器只写码，**不要在上面编译 / 构建**。
5. **每次用 Claude Code 前都要开梯子，而且是 TUN 模式下的链式代理** —— 见第六、七节，忘了不会有任何报错提醒你。
6. 会话按工作目录定位：两个 claude 跑在同一个目录时，`-c` 会串到另一个窗口。一任务一目录，或用 `/resume` 显式挑。

## 九、日常操作速查

| 想做的事 | 命令 |
|---|---|
| 一次性问一句 | `ssh <alias> "claude-safe -p '<问题>'"` |
| 进交互会话 | `ssh -t <alias> "cc"` |
| 看有哪些会话在跑 | `ssh <alias> "claude agents --json"` |
| 断线恢复 | tmux 里 `claude-safe --resume <sessionId>` |
| 查当前登录态 | `ssh <alias> "claude -p 'ping'"` |
| 查这次连接从哪来 | `ssh <alias> 'echo $SSH_CONNECTION'` |
