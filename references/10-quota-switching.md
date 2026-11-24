# 多账号额度轮换（2026-11 版）

> 作者：future ｜ 2026-11-24

单个 Claude 订阅有两个额度：**5 小时会话额度**和**每周额度**。跑长任务时，5 小时额度会在中途撞限，任务被硬断。

这一篇讲的是：怎么用两个（或多个）Pro/Max 订阅**轮流顶班**，让任务不断档，并且不让平台看出"这是同一台机器在反复换号"。

---

## 1. 为什么用响应头，而不是抓网页

Claude Code 每发一次请求，响应头里都带着额度的真实数字：

```
anthropic-ratelimit-unified-5h-utilization: 0.31
anthropic-ratelimit-unified-7d-utilization: 0.42
anthropic-ratelimit-unified-5h-reset: 1795369800
anthropic-ratelimit-unified-7d-reset: 1795870800
```

- `utilization` 是**已用比例**，`0.31` = 用了 31%
- `reset` 是**重置时间戳**，能精确算出"几点几分回血"

抓网页要开浏览器、解析 DOM、还会被改版打断；读响应头只要一次 1 token 的请求，**任何语言都能做**，而且拿到的是官方口径，不是估算。

探测请求本身几乎不消耗额度（`max_tokens: 1`），可以放心高频调用。

---

## 2. 阈值为什么是"剩 20%–30%"，还每次重抽

```
阈值 = 1 - random(0.20 ~ 0.30)     # 即 0.70 ~ 0.80
```

三个理由：

1. **给在跑的任务留收尾余量**：等到剩 2% 才切，正在生成的那一段很容易直接撞 429，前功尽弃；留 20% 足够一个中等任务收尾。
2. **每次重抽，不形成固定节奏**：固定阈值 = 固定时间点切换，长期看是一个可识别的周期信号。每次随机，行为更像"人"。
3. **越低越安全，太高会乒乓**：剩 30% 就切，两个号会互相踢。所以要配**最小驻留 30 分钟**——切过去 30 分钟内无论额度多低都不再切。

---

## 3. 检测间隔为什么是 12–20 分钟随机

- 固定 5 分钟一次：一天 288 次，节奏过于规整
- 12–20 分钟随机：一天 70–120 次，足够及时发现阈值，又不像机器

配合阈值 20–30%，最坏情况是"额度从 30% 掉到 0"只发生在 12 分钟内——正常任务很难跑这么快，够用。

---

## 4. 两个号都满了怎么办

不要立刻切。正确顺序：

```
1. 算出哪个号的 5h / 7d 最早重置（取两者更早的）
2. 等到那个时间点
3. 再等 random(30 ~ 60 分钟)      ← 关键
4. 才切过去
5. 给未完成的任务发「继续」
```

**为什么重置后还要等 30–60 分钟**：重置瞬间额度刚回满，此时大量用户同时涌入，平台侧压力最大、异常检测也最敏感。晚半小时再上，既避开高峰，也让"这个号刚睡醒就开始干活"看起来更自然。

---

## 5. 续跑：只发「继续」，而且要串行

切号会重启会话。重启后：

- **正在跑的任务**（面板底部有 `esc to interrupt`）→ 发「继续」
- **已经跑完的** → 什么都不发

多发一次"继续"会让它把已经做完的事再做一遍，浪费额度还可能改坏文件。

多个窗口时**不要并发发送**：

```
窗口 A 发「继续」→ 等 random(5~10 秒) → 窗口 B 发「继续」→ ...
```

同时往 5 个窗口灌输入，在终端层面就是一串密集的按键事件，既容易串窗口，也不像人在操作。

---

## 6. 重启必须保留原模型和推理强度

会话重启时如果无脑用默认参数，会出现：

- 原来用 `--model opus --effort max` 的任务，重启后掉回 sonnet/默认推理
- 输出质量突然下降，你还以为是"额度问题"

正确做法：**重启前从进程参数里把原配置读出来**，原样拼回去：

```bash
ps -eo args= -p <claude_pid>
# claude -c --model opus --effort max --permission-mode bypassPermissions
```

---

## 7. 完整实现

脚本：`scripts/quota-guard2.sh`（部署到 `/usr/local/bin/claude-quota-guard2`）

```bash
# 查看两个号的实时额度
claude-quota-guard2 --status

# 干跑（只打日志不切号）
DRY_RUN=1 claude-quota-guard2

# 正式跑（systemd 托管）
systemctl status claude-quota-guard2
```

systemd 单元：

```ini
[Unit]
Description=Claude multi-account quota guard v2
After=network-online.target

[Service]
Environment=HOME=/root
Environment=TZ=Asia/Shanghai
ExecStart=/usr/local/bin/claude-quota-guard2
Restart=always
RestartSec=20

[Install]
WantedBy=multi-user.target
```

开机自启：`systemctl enable --now claude-quota-guard2`

---

## 8. 加第二个号的正确姿势

```bash
# 在服务器 tmux 里跑，不要在本地跑
tmux new-session -d -s auth2 'claude setup-token'
tmux capture-pane -p -J -t auth2 | grep -oE 'https://claude.ai/oauth/[^ ]+'
```

拿到链接后，用**要添加的那个号**在浏览器里授权（浏览器出口必须和目标地区一致），把页面给的 code 粘回会话：

```bash
tmux send-keys -t auth2 -l '<code>'; tmux send-keys -t auth2 Enter
```

token 生成后立刻存成独立文件，**不要覆盖正在用的 active**：

```bash
printf '%s' '<sk-ant-oat01-...>' > /root/.claude/tokens/pro-20261124.env
chmod 600 /root/.claude/tokens/pro-20261124.env
```

---

## 9. 风险与边界

- 两个号**同一出口 IP 长期同时在线**，关联风险明显高于单号；能分环境就分
- 自动切换再平滑，也改变不了"同一台机器、同一个 IP、两个订阅"这个事实
- 额度是平台给的，规则随时会变；脚本要能随时停（`systemctl stop`）
- 不要把"自动切换"当成"防封"——它只解决**任务中断**，不解决**账号存活**
